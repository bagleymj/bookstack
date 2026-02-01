module Api
  module V1
    class TimelineController < ApplicationController
      before_action :authenticate_user!

      def index
        goals = current_user.reading_goals
                            .timeline_visible
                            .ordered_by_start
                            .includes(:book, :daily_quotas)

        render json: {
          timeline: {
            start_date: goals.minimum(:started_on) || Date.current,
            end_date: goals.maximum(:target_completion_date) || 3.months.from_now.to_date
          },
          goals: goals.map(&:as_timeline_data)
        }
      end

      def update
        goal = current_user.reading_goals.find(params[:id])
        goal.reschedule!(params[:start_date], params[:end_date])
        render json: goal.as_timeline_data
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end
end
