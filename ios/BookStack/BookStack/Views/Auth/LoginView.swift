import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.accent)
                    Text("BookStack")
                        .font(.largeTitle.bold())
                }

                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                }
                .padding(.horizontal)

                if let error = authManager.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task {
                        await authManager.signIn(email: email, password: password)
                    }
                } label: {
                    if authManager.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
                .padding(.horizontal)

                Button("Create Account") {
                    showRegister = true
                }
                .font(.subheadline)

                Spacer()
            }
            .sheet(isPresented: $showRegister) {
                RegisterView()
                    .environmentObject(authManager)
            }
        }
    }
}
