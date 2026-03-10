module Api
  module V1
    class PipelineController < ApplicationController
      before_action :authenticate_user!

      def index
        goals = current_user.reading_goals
                            .pipeline_visible
                            .ordered_by_start
                            .includes(:book, :daily_quotas)

        scheduler = ReadingListScheduler.new(current_user)

        render json: {
          pipeline: {
            start_date: goals.minimum(:started_on) || Date.current,
            end_date: goals.maximum(:target_completion_date) || 3.months.from_now.to_date
          },
          goals: goals.map(&:as_pipeline_data),
          includes_weekends: current_user.includes_weekends?,
          heijunka: scheduler.metrics
        }
      end

    end
  end
end
