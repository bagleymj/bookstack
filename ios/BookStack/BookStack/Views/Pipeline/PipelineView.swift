import SwiftUI
import Charts

struct PipelineView: View {
    @State private var goals: [PipelineGoal] = []
    @State private var pipelineInfo: PipelineInfo?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if goals.isEmpty {
                    ContentUnavailableView(
                        "No Reading Goals",
                        systemImage: "chart.bar",
                        description: Text("Create a reading goal to see your pipeline.")
                    )
                } else {
                    VStack(spacing: 20) {
                        PipelineChart(goals: goals.filter { $0.startDate != nil })
                            .frame(height: 300)
                            .padding()

                        // Goal list
                        ForEach(goals) { goal in
                            PipelineGoalRow(goal: goal)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Pipeline")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    func load() async {
        isLoading = true
        do {
            let response = try await APIClient.shared.fetchPipeline()
            goals = response.goals
            pipelineInfo = response.pipeline
        } catch {
            // Handle silently
        }
        isLoading = false
    }
}

struct PipelineChart: View {
    let goals: [PipelineGoal]

    var body: some View {
        Chart {
            ForEach(goals) { goal in
                if let startStr = goal.startDate,
                   let endStr = goal.endDate,
                   let start = dateFromString(startStr),
                   let end = dateFromString(endStr) {
                    RectangleMark(
                        xStart: .value("Start", start),
                        xEnd: .value("End", end),
                        y: .value("Minutes/Day", goal.minutesPerDay)
                    )
                    .foregroundStyle(colorForGoal(goal))
                    .opacity(goal.goalStatus == "completed" ? 0.5 : 0.8)
                    .annotation(position: .overlay) {
                        Text(goal.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxisLabel("Minutes/Day")
    }

    func dateFromString(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: str)
    }

    func colorForGoal(_ goal: PipelineGoal) -> Color {
        switch goal.goalStatus {
        case "completed": return .green
        case "abandoned": return .red
        case "queued": return .gray
        default:
            return goal.onTrack ? .blue : .orange
        }
    }
}

struct PipelineGoalRow: View {
    let goal: PipelineGoal

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.subheadline.bold())
                if let author = goal.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Label("\(goal.minutesPerDay) min/day", systemImage: "clock")
                    Label("\(goal.daysRemaining) days left", systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: goal.goalStatus)
                CircularProgress(progress: goal.progress / 100)
                    .frame(width: 28, height: 28)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
