import SwiftUI

struct WatchTimerView: View {
    let session: ReadingSession
    let onComplete: () async -> Void
    @State private var currentSession: ReadingSession?
    @State private var showComplete = false
    @State private var endPage: Int
    @State private var isCompleting = false
    @State private var completed = false
    @Environment(\.dismiss) var dismiss

    private var displaySession: ReadingSession {
        currentSession ?? session
    }

    init(session: ReadingSession, onComplete: @escaping () async -> Void) {
        self.session = session
        self.onComplete = onComplete
        self._endPage = State(initialValue: session.startPage)
    }

    var body: some View {
        if completed {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("Done!")
                    .font(.headline)
                Button("OK") {
                    Task { await onComplete() }
                    dismiss()
                }
            }
        } else if showComplete {
            WatchCompleteView(
                session: displaySession,
                endPage: $endPage,
                onSave: { await completeSession() }
            )
        } else {
            VStack(spacing: 8) {
                Text(displaySession.bookTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Timer display using TimelineView for Always-On
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let startDate = displaySession.startedAtDate {
                        let elapsed = context.date.timeIntervalSince(startDate)
                        Text(TimeFormatting.formatDuration(seconds: elapsed))
                            .font(.system(size: 36, weight: .light, design: .monospaced))
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await stopAndComplete() }
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .tint(.red)

                    Button {
                        showComplete = true
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .tint(.green)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    func stopAndComplete() async {
        do {
            let response = try await APIClient.shared.stopSession(id: displaySession.id)
            currentSession = response.readingSession
            showComplete = true
        } catch {
            // Handle error
        }
    }

    func completeSession() async {
        isCompleting = true
        do {
            _ = try await APIClient.shared.completeSession(id: displaySession.id, endPage: endPage)
            completed = true
        } catch {
            // Handle error
        }
        isCompleting = false
    }
}

struct WatchCompleteView: View {
    let session: ReadingSession
    @Binding var endPage: Int
    let onSave: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("End Page")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Digital Crown scrollable page picker
            Text("\(endPage)")
                .font(.system(size: 36, weight: .medium, design: .rounded))
                .focusable()
                .digitalCrownRotation(
                    $endPage,
                    from: session.startPage,
                    through: 9999,
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )

            Button {
                Task { await onSave() }
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
