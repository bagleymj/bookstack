class PipelineScheduler
  def initialize(pipeline)
    @pipeline = pipeline
    @user = pipeline.user
  end

  def schedule!
    schedule_by_track
  end

  private

  def schedule_by_track
    @pipeline.books_by_track.each do |track, pipeline_books|
      current_date = @pipeline.timeline_start_date

      pipeline_books.sort_by(&:position).each do |pb|
        # Calculate reading days needed
        days_needed = estimate_days(pb.book)

        pb.update!(
          planned_start_date: current_date,
          planned_end_date: current_date + days_needed.days
        )

        # Next book starts after this one ends
        current_date = pb.planned_end_date + 1.day
      end
    end
  end

  def estimate_days(book)
    # Estimate based on user's reading capacity
    hours_needed = book.estimated_reading_time_hours
    daily_reading_hours = daily_reading_capacity

    return 1 if daily_reading_hours.zero?

    (hours_needed / daily_reading_hours).ceil
  end

  def daily_reading_capacity
    # Default to 1 hour per day, could be made configurable
    stats = @user.user_reading_stats
    return 1.0 unless stats && stats.total_sessions.positive?

    # Calculate average daily reading time from recent history
    recent_sessions = @user.reading_sessions.completed.where("started_at > ?", 30.days.ago)
    return 1.0 if recent_sessions.empty?

    total_seconds = recent_sessions.sum(:duration_seconds)
    days_with_reading = recent_sessions.select(:started_at).distinct.count

    return 1.0 if days_with_reading.zero?

    average_daily_seconds = total_seconds / days_with_reading
    (average_daily_seconds / 3600.0).round(1)
  end
end
