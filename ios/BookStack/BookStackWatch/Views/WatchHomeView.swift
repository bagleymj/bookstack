import SwiftUI

struct WatchHomeView: View {
    @State private var activeSession: ReadingSession?
    @State private var books: [Book] = []
    @State private var todayQuotas: [DailyQuota] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                // Active session at top
                if let session = activeSession {
                    Section("Active Session") {
                        NavigationLink(destination: WatchTimerView(session: session, onComplete: load)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.bookTitle)
                                    .font(.headline)
                                    .lineLimit(1)
                                if let elapsed = session.elapsedSeconds {
                                    Text(TimeFormatting.formatDuration(seconds: elapsed))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }

                // Books currently reading
                Section("Start Session") {
                    ForEach(books) { book in
                        NavigationLink(destination: WatchStartSessionView(book: book, onStart: load)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                ProgressView(value: book.progressPercentage, total: 100)
                                    .tint(.accent)
                            }
                        }
                    }
                }

                // Today's quotas
                if !todayQuotas.isEmpty {
                    Section("Today") {
                        NavigationLink(destination: WatchTodayQuotaView(quotas: todayQuotas)) {
                            HStack {
                                let remaining = todayQuotas.reduce(0) { $0 + $1.estimatedMinutesRemaining }
                                Text("\(TimeFormatting.formatMinutes(remaining)) left")
                                    .font(.subheadline)
                                Spacer()
                                let done = todayQuotas.allSatisfy { $0.effectivelyComplete }
                                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(done ? .green : .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("BookStack")
            .task { await load() }
        }
    }

    func load() async {
        isLoading = true
        do {
            async let dashboardReq = APIClient.shared.fetchDashboard()
            async let booksReq = APIClient.shared.fetchBooks(status: "reading")

            let (dashboard, booksResp) = try await (dashboardReq, booksReq)
            activeSession = dashboard.today.activeSession
            todayQuotas = dashboard.today.quotas
            books = booksResp.books
        } catch {
            // Handle silently on watch
        }
        isLoading = false
    }
}
