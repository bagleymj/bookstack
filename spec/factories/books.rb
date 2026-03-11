FactoryBot.define do
  factory :book do
    user
    title { "Test Book" }
    author { "Test Author" }
    first_page { 1 }
    last_page { 300 }
    density { :average }
    owned { true }

    trait :reading do
      status { :reading }
      current_page { 50 }
    end

    trait :completed do
      status { :completed }
      current_page { 300 }
      completed_at { Time.current }
    end

    trait :unread do
      status { :unread }
    end

    trait :unowned do
      owned { false }
    end
  end
end
