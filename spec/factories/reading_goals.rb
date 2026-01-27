FactoryBot.define do
  factory :reading_goal do
    user { nil }
    book { nil }
    target_completion_date { "2026-01-26" }
    started_on { "2026-01-26" }
    include_weekends { false }
    status { 1 }
  end
end
