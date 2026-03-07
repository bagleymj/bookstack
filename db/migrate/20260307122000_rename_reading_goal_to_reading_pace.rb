class RenameReadingGoalToReadingPace < ActiveRecord::Migration[7.1]
  def change
    rename_column :users, :reading_goal_type, :reading_pace_type
    rename_column :users, :reading_goal_value, :reading_pace_value
    add_column :users, :reading_pace_set_on, :date
  end
end
