class DensityAnalyzer
  MINIMUM_SESSIONS = 3
  ADJUSTMENT_THRESHOLD = 0.15 # 15% difference triggers suggestion

  def initialize(book)
    @book = book
    @user = book.user
  end

  def analyze!
    return unless should_analyze?

    actual_modifier = calculate_actual_modifier
    return unless actual_modifier

    @book.update!(actual_density_modifier: actual_modifier)

    suggest_density_change(actual_modifier)
  end

  def suggested_density
    actual_modifier = @book.actual_density_modifier
    return nil unless actual_modifier

    # Find the closest density level
    Book::DENSITY_MODIFIERS.min_by { |_, v| (v - actual_modifier).abs }.first
  end

  def variance_from_expected
    return nil unless @book.actual_density_modifier

    expected = Book::DENSITY_MODIFIERS[@book.density.to_sym]
    ((@book.actual_density_modifier - expected) / expected * 100).round(1)
  end

  private

  def should_analyze?
    @book.reading_sessions.completed.count >= MINIMUM_SESSIONS
  end

  def calculate_actual_modifier
    sessions = @book.reading_sessions.completed
    return nil if sessions.empty?

    # Calculate average WPM for this book
    book_avg_wpm = sessions.average(:words_per_minute)
    return nil unless book_avg_wpm&.positive?

    # Compare to user's baseline WPM
    user_baseline = @user.effective_reading_speed

    # The modifier is how the user's speed on this book compares to baseline
    # If they read faster, modifier > 1.0 (lighter book)
    # If they read slower, modifier < 1.0 (denser book)
    (book_avg_wpm / user_baseline).round(2)
  end

  def suggest_density_change(actual_modifier)
    expected_modifier = Book::DENSITY_MODIFIERS[@book.density.to_sym]
    difference = (actual_modifier - expected_modifier).abs / expected_modifier

    return nil if difference < ADJUSTMENT_THRESHOLD

    suggested_density
  end
end
