class ReadingListController < ApplicationController
  before_action :authenticate_user!

  def show
    list_goals = current_user.reading_goals.in_reading_list.includes(:book)

    @currently_reading = list_goals.select { |g| g.active? && g.has_reading_sessions? }
    @up_next = list_goals.reject { |g| g.active? && g.has_reading_sessions? }
    @available_books = current_user.books
                                   .where.not(status: :completed)
                                   .where.not(id: current_user.reading_goals
                                                               .where(status: [:active, :queued])
                                                               .select(:book_id))
                                   .order(:title)
  end
end
