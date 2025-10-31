class UserBook < ApplicationRecord
  belongs_to :user
  belongs_to :book
  has_many :readthroughs

  validates :user_id, uniqueness: { scope: :book_id }
end
