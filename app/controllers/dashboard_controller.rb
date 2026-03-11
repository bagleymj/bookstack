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

    # Books with reading due today: books with today quotas first, then any in-progress books without quotas
    quota_books = @today_quotas.map { |q| q.reading_goal.book }
    other_in_progress = @books_in_progress.reject { |b| quota_books.include?(b) }
    @books_due_today = (quota_books + other_in_progress).first(3)
    @stats = current_user.user_reading_stats
    @up_next_goals = current_user.reading_goals
                                     .where(status: :queued)
                                     .where.not(started_on: nil)
                                     .order(:started_on)
                                     .includes(:book)
                                     .limit(5)
    @unread_books = current_user.books.unread.limit(5) if @up_next_goals.empty?

    # Yearly book counts (based on reading goals targeted for this year)
    yearly_goals = current_user.reading_goals.where(target_completion_date: Date.current.all_year)
    @yearly_books_scheduled = yearly_goals.select(:book_id).distinct.count
    @yearly_books_completed = yearly_goals.where(status: :completed).select(:book_id).distinct.count

    # Daily stats
    today_sessions = current_user.reading_sessions.completed.for_date(Date.current)
    @pages_today = today_sessions.sum(:pages_read)
    @time_today_seconds = today_sessions.sum(&:effective_duration_seconds).to_i

    # Weekly stats (Monday-Sunday)
    week_sessions = current_user.reading_sessions.completed
                      .where(started_at: Date.current.beginning_of_week(:monday).beginning_of_day..Date.current.end_of_day)
    @pages_this_week = week_sessions.sum(:pages_read)
    @time_this_week_seconds = week_sessions.sum(&:effective_duration_seconds).to_i

    # Derived stats
    if @stats && @stats.total_sessions > 0
      @pages_per_hour = ((@stats.average_wpm * 60.0) / Book::WORDS_PER_PAGE).round(1)
      @avg_pages_per_session = (@stats.total_pages_read.to_f / @stats.total_sessions).round(1)
      @avg_session_duration_seconds = @stats.total_reading_time_seconds / @stats.total_sessions
    else
      @pages_per_hour = 0
      @avg_pages_per_session = 0
      @avg_session_duration_seconds = 0
    end

    @books_completed_all_time = current_user.books.finished.count
    @reading_streak = calculate_reading_streak

    # Calculate total reading time remaining for today's quotas
    @today_reading_minutes = @today_quotas.sum(&:estimated_minutes_remaining)

    # Find goals with unresolved discrepancies from yesterday
    @goals_with_discrepancies = @active_goals.select(&:has_unresolved_discrepancy?)

    # Reading pace progress
    @reading_pace_progress = current_user.reading_pace_progress

    # Heijunka metrics (derived target, pace status, etc.)
    @heijunka = ReadingListScheduler.new(current_user).metrics
  end

  private

  def calculate_reading_streak
    dates = current_user.reading_sessions
              .completed
              .where(untracked: false)
              .pluck(:started_at)
              .map(&:to_date)
              .uniq
              .sort
              .reverse

    return 0 if dates.empty?

    streak = 0
    expected_date = Date.current

    # If no session today, check if yesterday starts the streak
    expected_date = Date.yesterday if dates.first != Date.current

    dates.each do |date|
      if date == expected_date
        streak += 1
        expected_date -= 1.day
      elsif date < expected_date
        break
      end
    end

    streak
  end
end
