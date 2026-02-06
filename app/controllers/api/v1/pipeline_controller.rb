module Api
  module V1
    class PipelineController < ApplicationController
      before_action :authenticate_user!

      def index
        goals = current_user.reading_goals
                            .pipeline_visible
                            .ordered_by_start
                            .includes(:book, :daily_quotas)

        render json: {
          pipeline: {
            start_date: goals.minimum(:started_on) || Date.current,
            end_date: goals.maximum(:target_completion_date) || 3.months.from_now.to_date
          },
          goals: goals.map(&:as_pipeline_data)
        }
      end

      def update
        goal = current_user.reading_goals.find(params[:id])
        new_start = params[:start_date].to_date
        new_end = params[:end_date].to_date

        # Check if goal has past activity that should be preserved
        session_bounds = goal.reading_session_boundaries
        has_past_activity = session_bounds[:has_sessions] && session_bounds[:earliest] < Date.current

        if has_past_activity && new_start > session_bounds[:earliest]
          # Goal has past sessions - use postpone to preserve them
          # The start stays anchored, only future quotas shift
          goal.postpone_remaining!(new_start, new_end)
        else
          # No past activity or moving earlier - full reschedule is fine
          goal.reschedule!(new_start, new_end)
        end

        render json: goal.as_pipeline_data
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end
end
