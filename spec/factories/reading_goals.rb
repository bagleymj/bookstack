FactoryBot.define do
  factory :reading_goal do
    user
    book
    started_on { Date.current }
    target_completion_date { 30.days.from_now.to_date }
    status { :active }
  end
end
