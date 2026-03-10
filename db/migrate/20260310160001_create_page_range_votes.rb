class CreatePageRangeVotes < ActiveRecord::Migration[7.1]
  def change
    create_table :page_range_votes do |t|
      t.references :edition, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :first_page, null: false
      t.integer :last_page, null: false

      t.timestamps
    end

    add_index :page_range_votes, [:edition_id, :user_id], unique: true
  end
end
