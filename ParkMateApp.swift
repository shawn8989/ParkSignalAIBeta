import SwiftUI

@main
struct ParkMateApp: App {
    @StateObject private var auth = AuthViewModel()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthViewModel
    
    var body: some View {
        if auth.isAuthenticated {
            DashboardView()
        } else {
            LandingView()
        }
    }
}
