class Book < ApplicationRecord
  has_many :user_books, dependent: :destroy
  has_many :users, through: :user_books
  has_one_attached :cover_image
  validates :title, presence: true
end
