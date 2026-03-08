class AddWeekendModeToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :weekend_mode, :integer, default: 1, null: false
    remove_column :reading_goals, :include_weekends, :boolean, default: true
  end
end
