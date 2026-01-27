class ReadingStatsCalculator
  def initialize(user)
    @user = user
  end

  def recalculate!
    stats = @user.user_reading_stats || @user.create_user_reading_stats!
    stats.recalculate!
  end
end
