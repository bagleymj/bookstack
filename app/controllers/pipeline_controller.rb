class PipelineController < ApplicationController
  before_action :authenticate_user!

  def show
    @reading_goals = current_user.reading_goals
                                  .pipeline_visible
                                  .ordered_by_start
                                  .includes(:book, :daily_quotas)
    @active_goals = current_user.reading_goals.active.ordered_by_start.includes(:book, :daily_quotas)
    @completed_goals = current_user.reading_goals.completed.includes(:book).limit(10)
  end
end
