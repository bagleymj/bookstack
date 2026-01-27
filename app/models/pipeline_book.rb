class PipelineBook < ApplicationRecord
  belongs_to :pipeline
  belongs_to :book

  # Validations
  validates :position, numericality: { greater_than_or_equal_to: 0 }
  validates :track, numericality: { greater_than: 0 }
  validates :book_id, uniqueness: { scope: :pipeline_id, message: "is already in this pipeline" }

  # Scopes
  scope :by_track, ->(track) { where(track: track) }
  scope :ordered, -> { order(:track, :position) }

  def user
    pipeline.user
  end

  def duration_days
    return nil unless planned_start_date && planned_end_date
    (planned_end_date - planned_start_date).to_i
  end

  def estimated_end_date
    return planned_end_date if planned_end_date
    return nil unless planned_start_date

    days_needed = (book.estimated_reading_time_hours / user.effective_daily_reading_hours).ceil
    planned_start_date + days_needed.days
  end

  def overlaps_with?(other)
    return false unless planned_start_date && planned_end_date
    return false unless other.planned_start_date && other.planned_end_date

    planned_start_date <= other.planned_end_date && planned_end_date >= other.planned_start_date
  end

  def as_timeline_data
    {
      id: id,
      book_id: book.id,
      title: book.title,
      author: book.author,
      track: track,
      start_date: planned_start_date&.to_s,
      end_date: planned_end_date&.to_s || estimated_end_date&.to_s,
      progress: book.progress_percentage,
      status: book.status,
      difficulty: book.difficulty,
      total_pages: book.total_pages,
      estimated_hours: book.estimated_reading_time_hours
    }
  end
end
