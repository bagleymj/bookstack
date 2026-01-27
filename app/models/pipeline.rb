class Pipeline < ApplicationRecord
  belongs_to :user
  has_many :pipeline_books, -> { order(:track, :position) }, dependent: :destroy
  has_many :books, through: :pipeline_books

  # Validations
  validates :name, presence: true

  # Scopes
  scope :active, -> { joins(:pipeline_books).distinct }

  def add_book(book, track: 1, planned_start_date: nil, planned_end_date: nil)
    position = pipeline_books.where(track: track).maximum(:position).to_i + 1

    pipeline_books.create!(
      book: book,
      track: track,
      position: position,
      planned_start_date: planned_start_date,
      planned_end_date: planned_end_date
    )
  end

  def remove_book(book)
    pipeline_books.find_by(book: book)&.destroy
  end

  def reorder_book(book, new_position, new_track: nil)
    pb = pipeline_books.find_by(book: book)
    return unless pb

    new_track ||= pb.track
    pb.update!(position: new_position, track: new_track)
    reposition_track!(new_track)
  end

  def total_estimated_time_hours
    pipeline_books.includes(:book).sum { |pb| pb.book.estimated_reading_time_hours }
  end

  def timeline_start_date
    pipeline_books.minimum(:planned_start_date) || Date.current
  end

  def timeline_end_date
    pipeline_books.maximum(:planned_end_date) || 1.year.from_now.to_date
  end

  def books_by_track
    pipeline_books.includes(:book).group_by(&:track)
  end

  def auto_schedule!
    PipelineScheduler.new(self).schedule!
  end

  private

  def reposition_track!(track)
    pipeline_books.where(track: track).order(:position).each_with_index do |pb, index|
      pb.update_column(:position, index + 1)
    end
  end
end
