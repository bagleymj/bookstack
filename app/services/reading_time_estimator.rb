class ReadingTimeEstimator
  def initialize(user)
    @user = user
  end

  def estimate_for_book(book)
    words = book.total_words
    effective_wpm = @user.effective_reading_speed * book.density_modifier

    minutes = (words / effective_wpm).round
    {
      minutes: minutes,
      hours: (minutes / 60.0).round(1),
      days: estimate_days(minutes),
      formatted: format_time(minutes)
    }
  end

  def estimate_for_pages(pages, density_modifier: 1.0)
    words = pages * Book::WORDS_PER_PAGE
    effective_wpm = @user.effective_reading_speed * density_modifier

    minutes = (words / effective_wpm).round
    format_time(minutes)
  end

  private

  def estimate_days(total_minutes)
    # Assume 1 hour of reading per day
    daily_minutes = 60
    (total_minutes.to_f / daily_minutes).ceil
  end

  def format_time(minutes)
    if minutes < 60
      "#{minutes} min"
    elsif minutes < 1440
      hours = (minutes / 60.0).round(1)
      "#{hours} hr"
    else
      days = (minutes / 1440.0).round(1)
      "#{days} days"
    end
  end
end
