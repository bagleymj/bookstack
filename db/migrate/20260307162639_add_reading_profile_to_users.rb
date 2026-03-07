class AddReadingProfileToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :max_concurrent_books, :integer, default: 1, null: false
    add_column :users, :weekday_reading_minutes, :integer, default: 60, null: false
    add_column :users, :weekend_reading_minutes, :integer, default: 60, null: false
  end
end
