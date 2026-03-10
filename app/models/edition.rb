class Edition < ApplicationRecord
  has_many :page_range_votes, dependent: :destroy

  validates :isbn, presence: true, uniqueness: true

  def recalculate_recommended_range!
    votes = page_range_votes.order(:created_at)
    if votes.empty?
      update!(recommended_first_page: nil, recommended_last_page: nil)
      return
    end

    first_pages = votes.pluck(:first_page).sort
    last_pages = votes.pluck(:last_page).sort

    update!(
      recommended_first_page: median(first_pages),
      recommended_last_page: median(last_pages)
    )
  end

  private

  def median(sorted_values)
    return nil if sorted_values.empty?
    mid = sorted_values.length / 2
    if sorted_values.length.odd?
      sorted_values[mid]
    else
      ((sorted_values[mid - 1] + sorted_values[mid]) / 2.0).round
    end
  end
end
