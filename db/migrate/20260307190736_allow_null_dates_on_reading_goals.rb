class AllowNullDatesOnReadingGoals < ActiveRecord::Migration[7.1]
  def change
    change_column_null :reading_goals, :target_completion_date, true
    change_column_null :reading_goals, :started_on, true
  end
end
