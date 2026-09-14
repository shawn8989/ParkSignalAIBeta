import SwiftUI
import SwiftData
import UserNotifications

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
struct ParkMateApp: App {
    let sharedModelContainer: ModelContainer

    init() {
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared

        let schema = Schema([
            User.self, Car.self, ParkingSpot.self, Restriction.self,
            CurrentParking.self, ParkSession.self, SignScan.self, PhotoBlob.self
        ])
        // Sync the user's own data across their devices via the CloudKit private
        // database (iCloud identity is the "account" — no login needed).
        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.SOTech.ParkSignalAI")
        )
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            // Local-first fallback: if CloudKit is unavailable or misconfigured,
            // keep working on-device only rather than failing to launch.
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}

struct RootView: View {
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
        .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
            OnboardingView { hasCompletedOnboarding = true }
        }
    }
}
