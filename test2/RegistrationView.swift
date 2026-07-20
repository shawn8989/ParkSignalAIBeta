import SwiftUI

struct RegistrationView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Create Account")) {
                    TextField("Username", text: $username)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                }
                // Avoid if-let inside builders on older toolchains
                if auth.errorMessage != nil {
                    Section {
                        Text(auth.errorMessage!)
                            .foregroundColor(.red)
                    }
                }
                Button("Register") {
                    auth.register(username: username, email: email, password: password)
                    if auth.isAuthenticated { dismiss() }
                }
                .disabled(username.isEmpty || email.isEmpty || password.isEmpty)
            }
            .navigationTitle("Register")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
