import Foundation
import SwiftUI

@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: AuthUser?
    @Published var isLoading = false
    @Published var error: String?

    init() {
        checkExistingToken()
        APIClient.shared.onUnauthorized = { [weak self] in
            Task { @MainActor in
                self?.signOutLocally()
            }
        }
    }

    private func checkExistingToken() {
        isAuthenticated = KeychainManager.shared.token != nil
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        error = nil
        do {
            let response = try await APIClient.shared.signIn(email: email, password: password)
            currentUser = response.user
            isAuthenticated = true
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func signUp(email: String, password: String, passwordConfirmation: String, name: String?) async {
        isLoading = true
        error = nil
        do {
            let response = try await APIClient.shared.signUp(
                email: email,
                password: password,
                passwordConfirmation: passwordConfirmation,
                name: name
            )
            currentUser = response.user
            isAuthenticated = true
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func signOut() async {
        do {
            try await APIClient.shared.signOut()
        } catch {
            // Sign out locally even if server request fails
        }
        signOutLocally()
    }

    private func signOutLocally() {
        KeychainManager.shared.clearAll()
        isAuthenticated = false
        currentUser = nil
    }
}
