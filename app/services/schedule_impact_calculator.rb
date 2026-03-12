# Calculates the change in daily reading load when adding a book to the reading list.
# Measures actual load impact: how many more (or fewer) minutes per day the user
# needs to read, amortized over the remaining pace period.
class ScheduleImpactCalculator
  def initialize(user)
    @user = user
  end

  # Returns a hash of { book_id => delta_minutes } for each candidate book.
  # Positive = adding the book increases daily load; negative = decreases it.
  def impacts_for(books)
    return {} unless throughput_pace?

    measure_actuals!
    current_load = compute_daily_load(current_pace_window)

    books.each_with_object({}) do |book, result|
      projected_load = compute_daily_load(pace_window_with(book))
      result[book.id] = (projected_load - current_load).round
    end
  end

  # Single-book convenience method
  def impact_for(book)
    impacts_for([book])[book.id] || 0
  end

  private

  def measure_actuals!
    @pace_start = @user.reading_pace_set_on || Date.current.beginning_of_year
    @days_elapsed = [(Date.current - @pace_start).to_i, 1].max
    @days_remaining = [365 - (Date.current - @pace_start).to_i, 1].max
    @actual_completed = @user.books
                             .where(status: :completed)
                             .where("completed_at >= ?", @pace_start.beginning_of_day)
                             .count
  end

  # Total reading time in the pace window divided by remaining reading days.
  # This measures the actual daily load commitment, not the pace-derived target.
  # When adding a book that doesn't displace another, the load always increases
  # by book_minutes / reading_days. When the window is full and a book is
  # displaced, the delta reflects the difference.
  def compute_daily_load(window)
    return 0.0 if window.empty?

    total_minutes = window.sum { |book| full_book_minutes(book) }.to_f
    reading_days = if @user.skip?
                     @days_remaining * 5.0 / 7
                   else
                     @days_remaining.to_f
                   end
    return 0.0 if reading_days <= 0

    total_minutes / reading_days
  end

  def current_pace_window
    build_pace_window(pace_window_size)
  end

  def pace_window_with(book)
    window = current_pace_window.dup

    # Insert the book at the end of the queue portion (before backfilled completions)
    queue_count = @user.reading_goals
                       .where(auto_scheduled: true)
                       .where.not(position: nil)
                       .where(status: [:queued, :active])
                       .count
    insert_at = [queue_count, window.size].min
    window.insert(insert_at, book)

    # Trim back to window size
    window.first(pace_window_size)
  end

  def build_pace_window(size)
    list_books = @user.reading_goals
                      .where(auto_scheduled: true)
                      .where.not(position: nil)
                      .where(status: [:queued, :active])
                      .includes(:book)
                      .order(:position)
                      .limit(size)
                      .map(&:book)

    return list_books if list_books.size >= size

    remaining_slots = size - list_books.size
    exclude_ids = list_books.map(&:id)
    completed = @user.books
                     .where(status: :completed)
                     .where.not(id: exclude_ids)
                     .order(completed_at: :desc)
                     .limit(remaining_slots)
                     .to_a

    list_books + completed
  end

  def full_book_minutes(book)
    wpm = book.actual_wpm || (@user.effective_reading_speed * book.density_modifier)
    return 60 if wpm.zero?
    (book.total_words.to_f / wpm).ceil
  end

  def pace_window_size
    [annual_pace.round, 1].max
  end

  def annual_pace
    return 0 unless @user.reading_pace_value&.positive?
    case @user.reading_pace_type
    when "books_per_year"  then @user.reading_pace_value.to_f
    when "books_per_month" then @user.reading_pace_value * 12.0
    when "books_per_week"  then @user.reading_pace_value * 52.0
    else 0
    end
  end

  def throughput_pace?
    %w[books_per_year books_per_month books_per_week].include?(@user.reading_pace_type) &&
      @user.reading_pace_value&.positive?
  end
end
