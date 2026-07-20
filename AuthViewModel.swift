import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isGuest = false
    @Published var currentUser: User?
    @Published var errorMessage: String?
    
    private var users: [User] = MockData.users
    
    func register(username: String, email: String, password: String) {
        guard !users.contains(where: { $0.email == email }) else {
            errorMessage = "Email already registered."
            return
        }
        let user = User(
            username: username,
            email: email,
            passwordHash: password.sha256
        )
        users.append(user)
        login(email: email, password: password)
    }
    
    func login(email: String, password: String) {
        isGuest = false
        guard let user = users.first(where: { $0.email == email && $0.passwordHash == password.sha256 }) else {
            errorMessage = "Invalid credentials."
            return
        }
        currentUser = user
        isAuthenticated = true
        errorMessage = nil
    }
    
    func logout() {
        currentUser = nil
        isAuthenticated = false
        isGuest = false
    }
    
    func continueAsGuest() {
        currentUser = nil
        isAuthenticated = false
        isGuest = true
        errorMessage = nil
    }
    
    func exitGuest() {
        isGuest = false
    }
}
