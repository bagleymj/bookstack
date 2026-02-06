class AddDiscrepancyAcknowledgedOnToReadingGoals < ActiveRecord::Migration[7.1]
  def change
    add_column :reading_goals, :discrepancy_acknowledged_on, :date
  end
end
