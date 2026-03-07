class AddQueueFieldsToReadingGoals < ActiveRecord::Migration[7.1]
  def change
    add_column :reading_goals, :position, :integer
    add_column :reading_goals, :auto_scheduled, :boolean, default: false, null: false
    add_index :reading_goals, [:user_id, :position]
  end
end
