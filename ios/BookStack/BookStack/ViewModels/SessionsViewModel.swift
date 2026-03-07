import Foundation

@MainActor
final class SessionsViewModel: ObservableObject {
    @Published var sessions: [ReadingSession] = []
    @Published var activeSession: ReadingSession?
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        do {
            async let sessionsReq = APIClient.shared.fetchSessions()
            async let activeReq = APIClient.shared.fetchActiveSession()

            let (sessionsResp, activeResp) = try await (sessionsReq, activeReq)
            sessions = sessionsResp.readingSessions
            activeSession = activeResp.readingSession
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func deleteSession(_ session: ReadingSession) async {
        do {
            try await APIClient.shared.deleteSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
