class CreateDailyQuota < ActiveRecord::Migration[7.1]
  def change
    create_table :daily_quotas do |t|
      t.references :reading_goal, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :target_pages, null: false
      t.integer :actual_pages, default: 0
      t.integer :status, default: 0

      t.timestamps
    end

    add_index :daily_quotas, [:reading_goal_id, :date], unique: true
    add_index :daily_quotas, :date
  end
end
