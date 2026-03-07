class ApplicationController < ActionController::Base
  before_action :redirect_to_onboarding
  helper_method :current_active_session

  private

  def redirect_to_onboarding
    return unless user_signed_in?
    return if devise_controller?
    return if is_a?(OnboardingController)
    return if self.class.module_parents.include?(Api)
    return if current_user.onboarding_completed_at.present?

    redirect_to onboarding_path
  end

  def current_active_session
    return nil unless user_signed_in?
    @current_active_session ||= current_user.reading_sessions.in_progress.includes(:book).first
  end
end
