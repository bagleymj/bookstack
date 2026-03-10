FactoryBot.define do
  factory :page_range_vote do
    edition
    user
    first_page { 1 }
    last_page { 280 }
  end
end
