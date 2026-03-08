module Api
  module V1
    class ProfilesController < BaseController
      def show
        render json: { profile: ProfileSerializer.new(current_user).as_json }
      end

      def update
        scheduling_fields = %w[max_concurrent_books weekday_reading_minutes weekend_reading_minutes weekend_mode]
        old_values = current_user.attributes.slice(*scheduling_fields)

        if current_user.update(profile_params)
          new_values = current_user.attributes.slice(*scheduling_fields)
          if old_values != new_values
            if current_user.reading_goals.where(auto_scheduled: true).exists?
              ReadingListScheduler.new(current_user).schedule!
            end
            regenerate_future_quotas!
          end
          render json: { profile: ProfileSerializer.new(current_user.reload).as_json }
        else
          render_errors current_user.errors.full_messages
        end
      end

      private

      def regenerate_future_quotas!
        current_user.reading_goals.active.includes(:book, :daily_quotas).find_each do |goal|
          from = [Date.current, goal.started_on].compact.max
          goal.daily_quotas.where("date >= ?", from).destroy_all
          goal.daily_quotas.reload
          ProfileAwareQuotaCalculator.new(goal, current_user).generate_quotas!(from_date: from)
        end
      end

      def profile_params
        params.require(:profile).permit(
          :name, :default_words_per_page, :default_reading_speed_wpm,
          :max_concurrent_books, :weekday_reading_minutes, :weekend_reading_minutes,
          :weekend_mode
        )
      end
    end
  end
end
