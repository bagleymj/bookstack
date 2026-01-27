FactoryBot.define do
  factory :reading_session do
    user { nil }
    book { nil }
    started_at { "2026-01-26 17:26:17" }
    ended_at { "2026-01-26 17:26:17" }
    start_page { 1 }
    end_page { 1 }
    duration_seconds { 1 }
    pages_read { 1 }
    words_per_minute { 1.5 }
  end
end
