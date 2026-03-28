class AddManuallyPlacedToReadingGoals < ActiveRecord::Migration[7.1]
  def change
    add_column :reading_goals, :manually_placed, :boolean, default: false, null: false
    add_column :reading_goals, :placement_tier, :string
    add_column :reading_goals, :postponed_until, :date
  end
end
