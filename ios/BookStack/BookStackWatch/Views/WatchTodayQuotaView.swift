import SwiftUI

struct WatchTodayQuotaView: View {
    let quotas: [DailyQuota]

    var body: some View {
        List {
            ForEach(quotas) { quota in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(quota.bookTitle ?? "Book")
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer()

                        if quota.effectivelyComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }

                    ProgressView(value: Double(quota.percentageComplete), total: 100)
                        .tint(quota.effectivelyComplete ? .green : .accent)

                    HStack {
                        Text("\(quota.actualPages)/\(quota.targetPages) pg")
                            .font(.caption2)
                        Spacer()
                        if quota.estimatedMinutesRemaining > 0 {
                            Text("\(quota.estimatedMinutesRemaining) min left")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Today")
    }
}
