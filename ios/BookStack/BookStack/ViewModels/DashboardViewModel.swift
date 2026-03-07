import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var dashboard: DashboardResponse?
    @Published var isLoading = false
    @Published var error: String?

    var todayQuotas: [DailyQuota] { dashboard?.today.quotas ?? [] }
    var activeSession: ReadingSession? { dashboard?.today.activeSession }
    var stats: StatsData? { dashboard?.stats }
    var discrepancies: [Discrepancy] { dashboard?.discrepancies ?? [] }
    var totalMinutesRemaining: Int { dashboard?.today.totalMinutesRemaining ?? 0 }
    var pagesReadToday: Int { dashboard?.today.pagesRead ?? 0 }
    var readingTimeToday: Int { dashboard?.today.readingTimeSeconds ?? 0 }

    func load() async {
        isLoading = true
        do {
            dashboard = try await APIClient.shared.fetchDashboard()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func resolveDiscrepancy(goalId: Int, strategy: String) async {
        do {
            _ = try await APIClient.shared.resolveDiscrepancy(goalId: goalId, strategy: strategy)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
