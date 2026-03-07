import SwiftUI

struct WatchLoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.title2)
                    .foregroundStyle(.accent)

                Text("BookStack")
                    .font(.headline)

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)

                SecureField("Password", text: $password)

                if let error = authManager.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        await authManager.signIn(email: email, password: password)
                    }
                } label: {
                    if authManager.isLoading {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(email.isEmpty || password.isEmpty)
            }
        }
    }
}
