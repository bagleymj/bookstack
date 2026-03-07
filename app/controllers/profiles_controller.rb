class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
  end

  def update
    scheduling_fields = %w[max_concurrent_books weekday_reading_minutes weekend_reading_minutes]
    old_values = current_user.attributes.slice(*scheduling_fields)

    if current_user.update(profile_params)
      new_values = current_user.attributes.slice(*scheduling_fields)
      if old_values != new_values && current_user.reading_goals.where(auto_scheduled: true).exists?
        ReadingListScheduler.new(current_user).schedule!
      end
      redirect_to profile_path, notice: "Profile updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(
      :name,
      :default_words_per_page,
      :default_reading_speed_wpm,
      :max_concurrent_books,
      :weekday_reading_minutes,
      :weekend_reading_minutes
    )
  end
end
