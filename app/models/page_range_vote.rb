class PageRangeVote < ApplicationRecord
  belongs_to :edition
  belongs_to :user

  validates :first_page, presence: true, numericality: { greater_than: 0 }
  validates :last_page, presence: true, numericality: { greater_than: 0 }
  validates :edition_id, uniqueness: { scope: :user_id }

  after_save :recalculate_edition_range
  after_destroy :recalculate_edition_range

  private

  def recalculate_edition_range
    edition.recalculate_recommended_range!
  end
end
