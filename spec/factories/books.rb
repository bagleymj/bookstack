FactoryBot.define do
  factory :book do
    user { nil }
    title { "MyString" }
    author { "MyString" }
    total_pages { 1 }
    words_per_page { 1 }
    current_page { 1 }
    status { 1 }
    difficulty { 1 }
    actual_difficulty_modifier { 1.5 }
    cover_image_url { "MyString" }
    isbn { "MyString" }
  end
end
