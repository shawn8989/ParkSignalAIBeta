import SwiftUI

struct LandingView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @State private var showLogin = false
    @State private var showRegister = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "car.fill")
                    .resizable()
                    .frame(width: 96, height: 64)
                    .foregroundColor(.accentColor)
                Text("Welcome to ParkMate")
                    .font(.largeTitle.bold())
                Text("Find legal parking, avoid tickets, and save time.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Spacer()
                VStack(spacing: 12) {
                    Button("Login") { showLogin = true }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    Button("Register") { showRegister = true }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("Continue as Guest") {
                        auth.continueAsGuest()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .sheet(isPresented: $showLogin) {
                LoginView()
                    .environmentObject(auth)
            }
            .sheet(isPresented: $showRegister) {
                RegistrationView()
                    .environmentObject(auth)
            }
        }
    }
}
