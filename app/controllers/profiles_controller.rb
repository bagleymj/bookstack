class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
  end

  def update
    scheduling_fields = %w[max_concurrent_books weekday_reading_minutes weekend_reading_minutes]
    old_values = current_user.attributes.slice(*scheduling_fields)

    cleaned_params = profile_params
    if cleaned_params[:reading_pace_type].blank?
      cleaned_params = cleaned_params.merge(reading_pace_type: nil, reading_pace_value: nil, reading_pace_set_on: nil)
    elsif current_user.reading_pace_type != cleaned_params[:reading_pace_type] ||
          current_user.reading_pace_value.to_s != cleaned_params[:reading_pace_value]
      # Reset the pace start date when the pace changes
      cleaned_params = cleaned_params.merge(reading_pace_set_on: Date.current)
    end

    if current_user.update(cleaned_params)
      current_user.apply_pace_to_schedule! if current_user.reading_pace_type.present?
      new_values = current_user.reload.attributes.slice(*scheduling_fields)
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
      :weekend_reading_minutes,
      :reading_pace_type,
      :reading_pace_value
    )
  end
end
