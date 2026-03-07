import SwiftUI

struct SessionsView: View {
    @StateObject private var viewModel = SessionsViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let active = viewModel.activeSession {
                    Section("Active Session") {
                        NavigationLink(destination: ActiveTimerView(session: active)) {
                            ActiveSessionRow(session: active)
                        }
                    }
                }

                Section("History") {
                    ForEach(viewModel.sessions.filter { !$0.inProgress }) { session in
                        SessionHistoryRow(session: session)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteSession(session) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Sessions")
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
        }
    }
}

struct ActiveSessionRow: View {
    let session: ReadingSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.bookTitle)
                    .font(.subheadline.bold())
                Text("Started at page \(session.startPage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let elapsed = session.elapsedSeconds {
                Text(TimeFormatting.formatDuration(seconds: elapsed))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.green)
            }
        }
    }
}

struct SessionHistoryRow: View {
    let session: ReadingSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.bookTitle)
                    .font(.subheadline.bold())
                HStack(spacing: 12) {
                    if let pages = session.pagesRead, pages > 0 {
                        Label("\(pages) pages", systemImage: "doc.text")
                    }
                    if let duration = session.formattedDuration {
                        Label(duration, systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let wpm = session.wordsPerMinute {
                Text("\(Int(wpm)) WPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if session.untracked {
                Image(systemName: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
