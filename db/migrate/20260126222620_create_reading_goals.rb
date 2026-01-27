class CreateReadingGoals < ActiveRecord::Migration[7.1]
  def change
    create_table :reading_goals do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.date :target_completion_date, null: false
      t.date :started_on, null: false
      t.boolean :include_weekends, default: true
      t.integer :status, default: 0

      t.timestamps
    end

    add_index :reading_goals, [:user_id, :book_id]
    add_index :reading_goals, [:user_id, :status]
  end
end
