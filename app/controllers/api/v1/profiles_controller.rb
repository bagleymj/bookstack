module Api
  module V1
    class ProfilesController < BaseController
      def show
        render json: { profile: ProfileSerializer.new(current_user).as_json }
      end

      def update
        scheduling_fields = %w[weekday_reading_minutes weekend_reading_minutes max_concurrent_books]
        old_values = current_user.attributes.slice(*scheduling_fields)

        if current_user.update(profile_params)
          new_values = current_user.attributes.slice(*scheduling_fields)
          if old_values != new_values && current_user.reading_goals.where(auto_scheduled: true).exists?
            ReadingListScheduler.new(current_user).schedule!
          end
          render json: { profile: ProfileSerializer.new(current_user.reload).as_json }
        else
          render_errors current_user.errors.full_messages
        end
      end

      private

      def profile_params
        params.require(:profile).permit(
          :name, :default_words_per_page, :default_reading_speed_wpm,
          :max_concurrent_books, :weekday_reading_minutes, :weekend_reading_minutes
        )
      end
    end
  end
end
