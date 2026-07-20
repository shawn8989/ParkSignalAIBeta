import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Login")) {
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
                Button("Login") {
                    auth.login(email: email, password: password)
                    if auth.isAuthenticated { dismiss() }
                }
                .disabled(email.isEmpty || password.isEmpty)
            }
            .navigationTitle("Login")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
