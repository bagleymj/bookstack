FactoryBot.define do
  factory :edition do
    sequence(:isbn) { |n| "978#{n.to_s.rjust(10, '0')}" }
    title { "Test Edition" }
    author { "Test Author" }
    publisher { "Test Publisher" }
    published_year { "2024" }
    page_count { 300 }
  end
end
