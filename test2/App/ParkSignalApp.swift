import SwiftUI
import SwiftData
import UserNotifications
import CoreData
import Combine

final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()
    private override init() { super.init() }

    // Show banner/sound/list even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Post notification log record for delivered notification
        NotificationCenter.default.post(name: Notification.Name("NotificationLog.Record"), object: nil, userInfo: [
            "event": "delivered",
            "notification": notification
        ])
        
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Post notification log record for responded notification
        NotificationCenter.default.post(name: Notification.Name("NotificationLog.Record"), object: nil, userInfo: [
            "event": "responded",
            "response": response
        ])
        
        completionHandler()
    }
}

@main
struct ParkSignalApp: App {
    let sharedModelContainer: ModelContainer?

    init() {
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared

        let schema = Schema([
            User.self, Car.self, ParkingSpot.self, Restriction.self,
            CurrentParking.self, ParkSession.self, SignScan.self, PhotoBlob.self
        ])
        // Sync the user's own data across their devices via the CloudKit private
        // database (iCloud identity is the "account" — no login needed).
        // Unsigned simulator processes lack CloudKit entitlements; initialization
        // can trap asynchronously, outside Swift error handling. A signed simulator
        // can explicitly opt in for the owner's authenticated sync verification.
        #if targetEnvironment(simulator)
        let useCloudKit = ProcessInfo.processInfo.arguments.contains("-EnableCloudKitSimulator")
        StorageStatus.shared.localOnlyReason = "This simulator uses local storage. Verify iCloud on a signed device, or enable CloudKit on a signed simulator."
        #else
        let useCloudKit = true
        #endif
        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: useCloudKit ? .private("iCloud.com.SOTech.ParkSignalAI") : .none
        )
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
            StorageStatus.shared.usesCloudStore = useCloudKit
        } catch {
            // Local-first fallback: if CloudKit is unavailable or misconfigured,
            // keep working on-device only rather than failing to launch.
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                sharedModelContainer = nil
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let sharedModelContainer {
                RootView().modelContainer(sharedModelContainer)
            } else {
                ContentUnavailableView("Saved Data Couldn’t Be Opened", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("No data was deleted. Restart the app and contact support if this continues. Do not delete the app while recovering your data."))
            }
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var issues = AppIssueStore.shared
    @AppStorage("alertLeadMinutes") private var leadMinutes = 15
    @AppStorage("parkingRemindersEnabledOnDevice") private var remindersEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        // Local-first: no accounts, open straight into the app.
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            SpotsMapView()
                .tabItem { Label("Map", systemImage: "map") }
            CarListView()
                .tabItem { Label("Cars", systemImage: "car") }
        }
        .task {
            do { try ImageStore.backfillReferencedPhotos(in: context) }
            catch { issues.message = "Some existing photos couldn't be prepared for sync: \(error.localizedDescription)" }
            await StorageStatus.shared.refreshAccount()
            await ReminderCoordinator.shared.reconcile(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task {
                await StorageStatus.shared.refreshAccount()
                await ReminderCoordinator.shared.reconcile(context: context)
            } }
        }
        .onChange(of: leadMinutes) { _, _ in Task { await ReminderCoordinator.shared.reconcile(context: context) } }
        .onChange(of: remindersEnabled) { _, _ in Task { await ReminderCoordinator.shared.reconcile(context: context) } }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { await ReminderCoordinator.shared.reconcile(context: context) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in
            Task { await ReminderCoordinator.shared.reconcile(context: context) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification).receive(on: RunLoop.main)) {
            StorageStatus.shared.handleCloudEvent($0)
        }
        .alert("Action Couldn't Be Completed", isPresented: Binding(get: { issues.message != nil }, set: { if !$0 { issues.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(issues.message ?? "") }
        .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
            OnboardingView { hasCompletedOnboarding = true }
        }
    }
}
