module Api
  module V1
    class ReadingGoalsController < BaseController
      before_action :set_goal, only: [
        :show, :destroy, :mark_completed, :mark_abandoned,
        :postpone, :unlock
      ]

      def index
        goals = current_user.reading_goals.includes(:book, :daily_quotas).ordered_by_start
        goals = goals.where(status: params[:status]) if params[:status].present?
        render json: { reading_goals: ReadingGoalSerializer.collection(goals) }
      end

      def show
        render json: {
          reading_goal: ReadingGoalSerializer.new(@goal).as_json_with_quotas
        }
      end

      def create
        goal = current_user.reading_goals.build(goal_params)
        if goal.save
          render json: { reading_goal: ReadingGoalSerializer.new(goal).as_json }, status: :created
        else
          render_errors goal.errors.full_messages
        end
      end

      def destroy
        was_auto_scheduled = @goal.auto_scheduled?
        @goal.destroy
        ReadingListScheduler.new(current_user).schedule! if was_auto_scheduled
        head :no_content
      end

      def mark_completed
        @goal.mark_completed!
        render json: { reading_goal: ReadingGoalSerializer.new(@goal.reload).as_json }
      end

      def mark_abandoned
        @goal.mark_abandoned!
        render json: { reading_goal: ReadingGoalSerializer.new(@goal.reload).as_json }
      end

      def postpone
        unless @goal.active? && @goal.auto_scheduled? && !@goal.manually_placed?
          render json: { errors: ["Only active auto-scheduled goals can be postponed"] }, status: :unprocessable_entity
          return
        end

        @goal.postpone!
        ReadingListScheduler.new(current_user).schedule!
        render json: { reading_goal: ReadingGoalSerializer.new(@goal.reload).as_json }
      end

      def unlock
        unless @goal.active? && @goal.manually_placed?
          render json: { errors: ["Only active manually placed goals can be unlocked"] }, status: :unprocessable_entity
          return
        end

        @goal.unlock!

        # Assign position at end of auto queue
        max_position = current_user.reading_goals.where.not(position: nil).maximum(:position) || 0
        @goal.update!(position: max_position + 1)

        ReadingListScheduler.new(current_user).schedule!
        render json: { reading_goal: ReadingGoalSerializer.new(@goal.reload).as_json }
      end

      private

      def set_goal
        @goal = current_user.reading_goals.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def goal_params
        params.require(:reading_goal).permit(
          :book_id, :started_on, :target_completion_date
        )
      end
    end
  end
end
