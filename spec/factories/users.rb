FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    name { "Test User" }
    default_words_per_page { 250 }
    default_reading_speed_wpm { 250 }
    max_concurrent_books { 3 }
    weekday_reading_minutes { 60 }
    weekend_reading_minutes { 90 }
  end
end
