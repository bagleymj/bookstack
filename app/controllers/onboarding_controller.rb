class OnboardingController < ApplicationController
  before_action :authenticate_user!
  layout "onboarding"

  def show
    redirect_to root_path if current_user.onboarding_completed_at.present?
  end

  def update
    cleaned_params = onboarding_params
    if cleaned_params[:reading_pace_type].blank?
      cleaned_params = cleaned_params.merge(reading_pace_type: nil, reading_pace_value: nil, reading_pace_set_on: nil)
    else
      cleaned_params = cleaned_params.merge(reading_pace_set_on: Date.current)
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
      :concurrency_limit,
      :reading_pace_type,
      :reading_pace_value
    )
  end
end
