class TimelineController < ApplicationController
  before_action :authenticate_user!

  def show
    @reading_goals = current_user.reading_goals
                                  .timeline_visible
                                  .ordered_by_start
                                  .includes(:book, :daily_quotas)
  end
end
