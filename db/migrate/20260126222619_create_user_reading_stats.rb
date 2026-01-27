class CreateUserReadingStats < ActiveRecord::Migration[7.1]
  def change
    create_table :user_reading_stats do |t|
      t.references :user, null: false, foreign_key: true
      t.float :average_wpm, default: 200.0
      t.integer :total_sessions, default: 0
      t.integer :total_pages_read, default: 0
      t.integer :total_reading_time_seconds, default: 0
      t.datetime :last_calculated_at

      t.timestamps
    end

    # Note: t.references already creates an index, so we remove and recreate with unique constraint
    remove_index :user_reading_stats, :user_id
    add_index :user_reading_stats, :user_id, unique: true
  end
end
