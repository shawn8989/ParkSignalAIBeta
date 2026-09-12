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
    init() {
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(for: [User.self, Car.self, ParkingSpot.self, Restriction.self, CurrentParking.self, ParkSession.self, SignScan.self])
        }
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
