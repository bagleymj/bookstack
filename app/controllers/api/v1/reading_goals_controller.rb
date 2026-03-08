module Api
  module V1
    class ReadingGoalsController < BaseController
      before_action :set_goal, only: [
        :show, :update, :destroy, :mark_completed, :mark_abandoned,
        :redistribute, :catch_up, :resolve_discrepancy
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

      def update
        old_dates = [ @goal.started_on, @goal.target_completion_date ]

        if @goal.update(goal_params)
          new_dates = [ @goal.started_on, @goal.target_completion_date ]
          if old_dates != new_dates
            @goal.daily_quotas.destroy_all
            @goal.daily_quotas.reload
            QuotaCalculator.new(@goal).generate_quotas!
          else
            @goal.redistribute_quotas!
          end

          render json: { reading_goal: ReadingGoalSerializer.new(@goal.reload).as_json }
        else
          render_errors @goal.errors.full_messages
        end
      end

      def destroy
        @goal.destroy
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

      def redistribute
        @goal.redistribute_quotas!
        render json: { reading_goal: ReadingGoalSerializer.new(@goal.reload).as_json_with_quotas }
      end

      def catch_up
        @goal.catch_up!
        render json: { reading_goal: ReadingGoalSerializer.new(@goal.reload).as_json_with_quotas }
      end

      def resolve_discrepancy
        strategy = params[:strategy]&.to_sym
        unless [ :redistribute, :apply_to_today ].include?(strategy)
          return render_error("Invalid strategy. Use 'redistribute' or 'apply_to_today'")
        end

        @goal.resolve_discrepancy!(strategy)
        render json: { reading_goal: ReadingGoalSerializer.new(@goal.reload).as_json_with_quotas }
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
