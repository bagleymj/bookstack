import SwiftUI

struct ActiveTimerView: View {
    let session: ReadingSession
    @State private var currentSession: ReadingSession?
    @State private var showComplete = false
    @State private var endPage = ""
    @State private var error: String?
    @State private var isCompleted = false
    @Environment(\.dismiss) var dismiss

    private var displaySession: ReadingSession {
        currentSession ?? session
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Book title
            Text(displaySession.bookTitle)
                .font(.title3)
                .foregroundStyle(.secondary)

            // Timer - uses TimelineView for 1-second updates
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let startDate = displaySession.startedAtDate, displaySession.inProgress {
                    let elapsed = context.date.timeIntervalSince(startDate)
                    Text(TimeFormatting.formatDuration(seconds: elapsed))
                        .font(.system(size: 64, weight: .light, design: .monospaced))
                } else if let duration = displaySession.durationSeconds {
                    Text(TimeFormatting.formatDuration(seconds: TimeInterval(duration)))
                        .font(.system(size: 64, weight: .light, design: .monospaced))
                }
            }

            Text("Started at page \(displaySession.startPage)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if let error = error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if isCompleted {
                Label("Session Complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                    .padding()

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            } else if showComplete {
                // End page input
                VStack(spacing: 16) {
                    Text("What page did you finish on?")
                        .font(.headline)

                    TextField("End Page", text: $endPage)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .multilineTextAlignment(.center)
                        .font(.title2)

                    Button {
                        Task { await completeSession() }
                    } label: {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(endPage.isEmpty)
                }
                .padding(.horizontal, 40)
            } else if displaySession.inProgress {
                HStack(spacing: 16) {
                    Button {
                        Task { await stopSession() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button {
                        showComplete = true
                    } label: {
                        Label("Complete", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            } else if displaySession.endedAt != nil && displaySession.endPage == nil {
                // Stopped but not completed
                VStack(spacing: 16) {
                    Text("What page did you finish on?")
                        .font(.headline)

                    TextField("End Page", text: $endPage)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .multilineTextAlignment(.center)
                        .font(.title2)

                    Button {
                        Task { await completeSession() }
                    } label: {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(endPage.isEmpty)
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .navigationBarBackButtonHidden(displaySession.inProgress)
    }

    func stopSession() async {
        do {
            let response = try await APIClient.shared.stopSession(id: displaySession.id)
            currentSession = response.readingSession
            showComplete = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func completeSession() async {
        guard let page = Int(endPage) else { return }
        do {
            let response = try await APIClient.shared.completeSession(id: displaySession.id, endPage: page)
            currentSession = response.readingSession
            isCompleted = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
