import SwiftUI

struct WatchStartSessionView: View {
    let book: Book
    let onStart: () async -> Void
    @State private var isStarting = false
    @State private var startedSession: ReadingSession?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        if let session = startedSession {
            WatchTimerView(session: session, onComplete: onStart)
        } else {
            VStack(spacing: 16) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("Page \(book.currentPage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await startSession() }
                } label: {
                    if isStarting {
                        ProgressView()
                    } else {
                        Label("Start", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }

    func startSession() async {
        isStarting = true
        do {
            let response = try await APIClient.shared.startSession(bookId: book.id)
            startedSession = response.readingSession
        } catch {
            // Show error or dismiss
        }
        isStarting = false
    }
}
