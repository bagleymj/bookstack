class CreateReadingSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :reading_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :start_page, null: false
      t.integer :end_page
      t.integer :duration_seconds
      t.integer :pages_read
      t.float :words_per_minute

      t.timestamps
    end

    add_index :reading_sessions, [:user_id, :started_at]
    add_index :reading_sessions, [:book_id, :started_at]
  end
end
