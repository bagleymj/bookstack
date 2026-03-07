import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name (optional)", text: $name)
                        .textContentType(.name)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Confirm Password", text: $passwordConfirmation)
                        .textContentType(.newPassword)
                }

                if let error = authManager.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        Task {
                            await authManager.signUp(
                                email: email,
                                password: password,
                                passwordConfirmation: passwordConfirmation,
                                name: name.isEmpty ? nil : name
                            )
                            if authManager.isAuthenticated { dismiss() }
                        }
                    } label: {
                        if authManager.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create Account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || password != passwordConfirmation || authManager.isLoading)
                }
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
