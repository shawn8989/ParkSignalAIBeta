import SwiftUI

struct LandingView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @State private var showLogin = false
    @State private var showRegister = false
    
    var body: some View {
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
            HStack(spacing: 16) {
                Button("Login") { showLogin = true }
                    .buttonStyle(.borderedProminent)
                Button("Register") { showRegister = true }
                    .buttonStyle(.bordered)
            }
            .padding(.bottom)
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
        .sheet(isPresented: $showRegister) {
            RegisterView()
        }
    }
}
