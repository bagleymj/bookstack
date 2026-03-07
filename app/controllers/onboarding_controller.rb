class OnboardingController < ApplicationController
  before_action :authenticate_user!
  layout "onboarding"

  def show
    redirect_to root_path if current_user.onboarding_completed_at.present?
  end

  def update
    cleaned_params = onboarding_params
    if cleaned_params[:reading_goal_type].blank?
      cleaned_params = cleaned_params.merge(reading_goal_type: nil, reading_goal_value: nil)
    end

    if current_user.update(cleaned_params.merge(onboarding_completed_at: Time.current))
      redirect_to root_path, notice: "Welcome to BookStack! You're all set."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def skip
    current_user.update!(onboarding_completed_at: Time.current)
    redirect_to root_path
  end

  private

  def onboarding_params
    params.require(:user).permit(
      :name,
      :default_words_per_page,
      :default_reading_speed_wpm,
      :weekday_reading_minutes,
      :weekend_reading_minutes,
      :max_concurrent_books,
      :reading_goal_type,
      :reading_goal_value
    )
  end
end
