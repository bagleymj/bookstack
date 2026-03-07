import SwiftUI

struct BookDetailView: View {
    let bookId: Int
    @State private var book: Book?
    @State private var activeGoal: ReadingGoal?
    @State private var recentSessions: [ReadingSession] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if let book = book {
                VStack(alignment: .leading, spacing: 20) {
                    // Book Header
                    BookHeader(book: book)

                    // Progress
                    if book.isReading {
                        ProgressSection(book: book)
                    }

                    // Active Goal
                    if let goal = activeGoal {
                        GoalSection(goal: goal)
                    }

                    // Actions
                    ActionSection(book: book, onAction: load)

                    // Recent Sessions
                    if !recentSessions.isEmpty {
                        SessionsSection(sessions: recentSessions)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(book?.title ?? "Book")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    func load() async {
        isLoading = true
        do {
            let response = try await APIClient.shared.fetchBook(id: bookId)
            book = response.book
            activeGoal = response.activeGoal
            recentSessions = response.recentSessions
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private struct BookHeader: View {
    let book: Book

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .frame(width: 80, height: 120)
                .overlay {
                    if let url = book.coverImageUrl, let imageUrl = URL(string: url) {
                        AsyncImage(url: imageUrl) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "book.closed.fill")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "book.closed.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.title3.bold())
                if let author = book.author {
                    Text(author)
                        .foregroundStyle(.secondary)
                }
                StatusBadge(status: book.status)
                Text("\(book.totalPages) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if book.estimatedReadingTimeMinutes > 0 {
                    Text("\(TimeFormatting.formatMinutes(book.estimatedReadingTimeMinutes)) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ProgressSection: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress")
                .font(.headline)
            ProgressView(value: book.progressPercentage, total: 100)
            HStack {
                Text("Page \(book.currentPage) of \(book.lastPage)")
                    .font(.caption)
                Spacer()
                Text("\(Int(book.progressPercentage))%")
                    .font(.caption.bold())
            }
            .foregroundStyle(.secondary)
        }
    }
}

private struct GoalSection: View {
    let goal: ReadingGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading Goal")
                .font(.headline)

            HStack {
                Label("\(goal.pagesPerDay) pages/day", systemImage: "book.pages")
                Spacer()
                Label("\(goal.daysRemaining) days left", systemImage: "calendar")
            }
            .font(.subheadline)

            if let quota = goal.todayQuota {
                HStack {
                    Text("Today: \(quota.actualPages)/\(quota.targetPages) pages")
                    Spacer()
                    if quota.effectivelyComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ActionSection: View {
    let book: Book
    let onAction: () async -> Void

    var body: some View {
        VStack(spacing: 8) {
            if book.isUnread {
                Button {
                    Task {
                        _ = try? await APIClient.shared.startReading(bookId: book.id)
                        await onAction()
                    }
                } label: {
                    Label("Start Reading", systemImage: "book.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if book.isReading {
                NavigationLink {
                    StartSessionView(book: book)
                } label: {
                    Label("Start Session", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        _ = try? await APIClient.shared.markBookCompleted(bookId: book.id)
                        await onAction()
                    }
                } label: {
                    Label("Mark Completed", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct SessionsSection: View {
    let sessions: [ReadingSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Sessions")
                .font(.headline)

            ForEach(sessions) { session in
                HStack {
                    VStack(alignment: .leading) {
                        Text("Pages \(session.startPage)-\(session.endPage ?? 0)")
                            .font(.subheadline)
                        Text(session.formattedDuration ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let wpm = session.wordsPerMinute {
                        Text("\(Int(wpm)) WPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                Divider()
            }
        }
    }
}
