class PipelineController < ApplicationController
  before_action :authenticate_user!

  def show
    @reading_goals = current_user.reading_goals
                                  .pipeline_visible
                                  .ordered_by_start
                                  .includes(:book, :daily_quotas)
    @completed_goals = current_user.reading_goals.completed.includes(:book).limit(10)

    # Reading list data
    list_goals = current_user.reading_goals.in_reading_list.includes(:book, :daily_quotas)
    manual_goals = current_user.reading_goals
                               .where(manually_placed: true, status: [:active, :queued])
                               .includes(:book, :daily_quotas).to_a
    all_active = (list_goals + manual_goals).uniq(&:id)
    @currently_reading = all_active.select { |g| g.active? && (g.has_reading_sessions? || g.manually_placed?) }
    @up_next = list_goals.reject { |g| g.active? && g.has_reading_sessions? }
    @available_books = current_user.books
                                   .where.not(status: :completed)
                                   .where.not(id: current_user.reading_goals
                                                               .where(status: [:active, :queued])
                                                               .select(:book_id))
                                   .order(:title)
    @book_impacts = ScheduleImpactCalculator.new(current_user).impacts_for(@available_books)

    # Warn about unowned books starting next week
    next_monday = Date.current.beginning_of_week(:monday) + 7
    next_sunday = next_monday + 6
    @unowned_next_week = current_user.reading_goals
      .where(status: [:active, :queued])
      .where(started_on: next_monday..next_sunday)
      .includes(:book)
      .select { |g| !g.book.owned? }
  end
end
