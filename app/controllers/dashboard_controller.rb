class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @books_in_progress = current_user.books.in_progress.includes(:reading_goals)
    @recent_sessions = current_user.reading_sessions.completed.recent.limit(5).includes(:book)
    @active_goals = current_user.reading_goals.active.includes(:book, :daily_quotas)
    @today_quotas = DailyQuota.joins(:reading_goal)
                              .where(reading_goals: { user_id: current_user.id, status: :active })
                              .where(date: Date.current)
                              .where.not(status: :missed)  # Don't show missed quotas as active goals
                              .includes(reading_goal: :book)
    @stats = current_user.user_reading_stats
    @unread_books = current_user.books.unread.limit(5)

    # Calculate total reading time remaining for today's quotas
    @today_reading_minutes = @today_quotas.sum(&:estimated_minutes_remaining)

    # Find goals with unresolved discrepancies from yesterday
    @goals_with_discrepancies = @active_goals.select(&:has_unresolved_discrepancy?)
  end
end
