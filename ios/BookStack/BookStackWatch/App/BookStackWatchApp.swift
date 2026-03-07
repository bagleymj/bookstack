import SwiftUI

@main
struct BookStackWatchApp: App {
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                WatchHomeView()
                    .environmentObject(authManager)
            } else {
                WatchLoginView()
                    .environmentObject(authManager)
            }
        }
    }
}
