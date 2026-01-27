class DailyQuotasController < ApplicationController
  before_action :authenticate_user!
  before_action :set_daily_quota

  def update
    if @daily_quota.update(daily_quota_params)
      redirect_to @daily_quota.reading_goal, notice: "Quota updated."
    else
      redirect_to @daily_quota.reading_goal, alert: "Could not update quota."
    end
  end

  private

  def set_daily_quota
    @daily_quota = DailyQuota.joins(reading_goal: :user)
                              .where(users: { id: current_user.id })
                              .find(params[:id])
  end

  def daily_quota_params
    params.require(:daily_quota).permit(:actual_pages)
  end
end
