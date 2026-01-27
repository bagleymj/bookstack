class CreateBooks < ActiveRecord::Migration[7.1]
  def change
    create_table :books do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :author
      t.integer :total_pages, null: false
      t.integer :words_per_page, default: 250
      t.integer :current_page, default: 0
      t.integer :status, default: 0
      t.integer :difficulty, default: 3
      t.float :actual_difficulty_modifier
      t.string :cover_image_url
      t.string :isbn

      t.timestamps
    end

    add_index :books, [:user_id, :status]
    add_index :books, :isbn
  end
end
