FactoryBot.define do
  factory :user_reading_stat do
    user { nil }
    average_wpm { 1.5 }
    total_sessions { 1 }
    total_pages_read { 1 }
    total_reading_time_seconds { 1 }
    last_calculated_at { "2026-01-26 17:26:19" }
  end
end
