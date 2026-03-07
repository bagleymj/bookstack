import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Active Session Banner
                    if let session = viewModel.activeSession {
                        ActiveSessionBanner(session: session)
                    }

                    // Today's Reading
                    TodaySection(viewModel: viewModel)

                    // Discrepancies
                    if !viewModel.discrepancies.isEmpty {
                        DiscrepancySection(viewModel: viewModel)
                    }

                    // Stats
                    if let stats = viewModel.stats {
                        StatsSection(stats: stats)
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
        }
    }
}

// MARK: - Active Session Banner

struct ActiveSessionBanner: View {
    let session: ReadingSession

    var body: some View {
        NavigationLink(destination: ActiveTimerView(session: session)) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reading Now")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(session.bookTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                if let elapsed = session.elapsedSeconds {
                    Text(TimeFormatting.formatDuration(seconds: elapsed))
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(.white)
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding()
            .background(.green.gradient, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Today Section

struct TodaySection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today")
                    .font(.title2.bold())
                Spacer()
                if viewModel.totalMinutesRemaining > 0 {
                    Text("\(TimeFormatting.formatMinutes(viewModel.totalMinutesRemaining)) left")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.todayQuotas.isEmpty {
                Text("No reading goals for today.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.todayQuotas) { quota in
                    QuotaRow(quota: quota)
                }
            }

            HStack(spacing: 24) {
                StatBadge(title: "Pages", value: "\(viewModel.pagesReadToday)")
                StatBadge(title: "Time", value: TimeFormatting.formatMinutes(viewModel.readingTimeToday / 60))
            }
        }
    }
}

struct QuotaRow: View {
    let quota: DailyQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(quota.bookTitle ?? "Book")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(quota.actualPages)/\(quota.targetPages) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(quota.percentageComplete), total: 100)
                .tint(quota.effectivelyComplete ? .green : .accent)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Discrepancy Section

struct DiscrepancySection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Needs Attention")
                .font(.title3.bold())

            ForEach(viewModel.discrepancies, id: \.goalId) { disc in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: disc.type == "behind" ? "exclamationmark.triangle.fill" : "arrow.up.circle.fill")
                            .foregroundStyle(disc.type == "behind" ? .orange : .green)
                        Text(disc.bookTitle)
                            .font(.subheadline.bold())
                    }
                    Text(disc.type == "behind"
                         ? "\(disc.pages) pages behind yesterday"
                         : "\(disc.pages) pages ahead yesterday")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Redistribute") {
                            Task { await viewModel.resolveDiscrepancy(goalId: disc.goalId, strategy: "redistribute") }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Button("Apply to Today") {
                            Task { await viewModel.resolveDiscrepancy(goalId: disc.goalId, strategy: "apply_to_today") }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Stats Section

struct StatsSection: View {
    let stats: StatsData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(.title3.bold())

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatBadge(title: "Streak", value: "\(stats.readingStreak)", icon: "flame.fill")
                StatBadge(title: "Reading", value: "\(stats.booksInProgress)")
                StatBadge(title: "Completed", value: "\(stats.booksCompletedAllTime)")
                StatBadge(title: "This Week", value: "\(stats.pagesThisWeek) pg")
                StatBadge(title: "Avg WPM", value: stats.averageWpm.map { String(Int($0)) } ?? "-")
                StatBadge(title: "Total Time", value: stats.totalReadingTimeFormatted)
            }
        }
    }
}

struct StatBadge: View {
    let title: String
    let value: String
    var icon: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                Text(value)
                    .font(.headline)
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
