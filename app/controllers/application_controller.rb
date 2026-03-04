class ApplicationController < ActionController::Base
  helper_method :current_active_session

  private

  def current_active_session
    return nil unless user_signed_in?
    @current_active_session ||= current_user.reading_sessions.in_progress.includes(:book).first
  end
end
