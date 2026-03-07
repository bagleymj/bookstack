FactoryBot.define do
  factory :daily_quota do
    reading_goal
    date { Date.current }
    target_pages { 10 }
    actual_pages { 0 }
    status { :pending }
  end
end
