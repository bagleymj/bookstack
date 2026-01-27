FactoryBot.define do
  factory :pipeline_book do
    pipeline { nil }
    book { nil }
    position { 1 }
    planned_start_date { "2026-01-26" }
    planned_end_date { "2026-01-26" }
    track { 1 }
  end
end
