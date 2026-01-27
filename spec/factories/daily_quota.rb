FactoryBot.define do
  factory :daily_quotum do
    reading_goal { nil }
    date { "2026-01-26" }
    target_pages { 1 }
    actual_pages { 1 }
    status { 1 }
  end
end
