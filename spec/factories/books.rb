FactoryBot.define do
  factory :book do
    user
    title { "Test Book" }
    author { "Test Author" }
    first_page { 1 }
    last_page { 300 }
    difficulty { :average }

    trait :reading do
      status { :reading }
      current_page { 50 }
    end

    trait :completed do
      status { :completed }
      current_page { 300 }
    end

    trait :unread do
      status { :unread }
    end
  end
end
