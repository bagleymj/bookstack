FactoryBot.define do
  factory :reading_session do
    user
    book
    started_at { 1.hour.ago }
    start_page { 1 }

    trait :completed do
      ended_at { Time.current }
      end_page { 20 }
      duration_seconds { 3600 }
      pages_read { 19 }
    end

    trait :in_progress do
      ended_at { nil }
      end_page { nil }
    end
  end
end
