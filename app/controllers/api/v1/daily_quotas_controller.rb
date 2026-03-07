module Api
  module V1
    class DailyQuotasController < BaseController
      def update
        quota = DailyQuota.joins(:reading_goal)
                          .where(reading_goals: { user_id: current_user.id })
                          .find(params[:id])

        quota.record_pages!(params[:actual_pages].to_i)
        render json: { daily_quota: DailyQuotaSerializer.new(quota.reload).as_json }
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end
    end
  end
end
