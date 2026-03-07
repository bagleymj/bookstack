class PipelineController < ApplicationController
  before_action :authenticate_user!

  def show
    @reading_goals = current_user.reading_goals
                                  .pipeline_visible
                                  .ordered_by_start
                                  .includes(:book, :daily_quotas)
    @active_goals = current_user.reading_goals.active.ordered_by_start.includes(:book, :daily_quotas)
    @completed_goals = current_user.reading_goals.completed.includes(:book).limit(10)

    # Books eligible for new pipeline goals
    books_with_active_goals = current_user.reading_goals.active.select(:book_id)
    @available_books = current_user.books
                                   .where.not(status: :completed)
                                   .where.not(id: books_with_active_goals)
                                   .order(:title)
  end
end
