class ReplaceYearlyGoalWithFlexibleGoal < ActiveRecord::Migration[7.1]
  def change
    remove_column :users, :yearly_book_goal, :integer
    add_column :users, :reading_goal_type, :string
    add_column :users, :reading_goal_value, :integer
  end
end
