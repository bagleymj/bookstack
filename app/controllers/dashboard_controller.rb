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

    # Yearly book counts (based on reading goals targeted for this year)
    yearly_goals = current_user.reading_goals.where(target_completion_date: Date.current.all_year)
    @yearly_books_scheduled = yearly_goals.select(:book_id).distinct.count
    @yearly_books_completed = yearly_goals.where(status: :completed).select(:book_id).distinct.count

    # Calculate total reading time remaining for today's quotas
    @today_reading_minutes = @today_quotas.sum(&:estimated_minutes_remaining)

    # Find goals with unresolved discrepancies from yesterday
    @goals_with_discrepancies = @active_goals.select(&:has_unresolved_discrepancy?)
  end
end
