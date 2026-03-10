class CreateEditions < ActiveRecord::Migration[7.1]
  def change
    create_table :editions do |t|
      t.string :isbn, null: false
      t.string :google_books_id
      t.string :title
      t.string :author
      t.string :publisher
      t.string :published_year
      t.integer :page_count
      t.string :cover_image_url
      t.string :format
      t.integer :recommended_first_page
      t.integer :recommended_last_page
      t.integer :page_range_votes_count, default: 0

      t.timestamps
    end

    add_index :editions, :isbn, unique: true
    add_index :editions, :google_books_id
  end
end
