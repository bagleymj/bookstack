import SwiftUI

struct StartSessionView: View {
    let book: Book
    @Environment(\.dismiss) var dismiss
    @State private var session: ReadingSession?
    @State private var error: String?

    var body: some View {
        if let session = session {
            ActiveTimerView(session: session)
        } else {
            VStack(spacing: 24) {
                Text("Start Reading")
                    .font(.title2.bold())

                Text(book.title)
                    .font(.headline)

                Text("Starting at page \(book.currentPage)")
                    .foregroundStyle(.secondary)

                if let error = error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button {
                    Task { await startSession() }
                } label: {
                    Label("Start Timer", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }
        }
    }

    func startSession() async {
        do {
            let response = try await APIClient.shared.startSession(bookId: book.id)
            session = response.readingSession
        } catch {
            self.error = error.localizedDescription
        }
    }
}
