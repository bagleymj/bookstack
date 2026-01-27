# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
ActiveSupport::Inflector.inflections(:en) do |inflect|
  # UserReadingStats is singular (one stats record per user)
  inflect.irregular "user_reading_stats", "user_reading_stats"

  # DailyQuota - quota is singular
  inflect.irregular "daily_quota", "daily_quotas"
  inflect.irregular "quota", "quotas"
end
