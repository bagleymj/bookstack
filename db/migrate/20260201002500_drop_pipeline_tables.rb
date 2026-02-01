class DropPipelineTables < ActiveRecord::Migration[7.1]
  def up
    drop_table :pipeline_books
    drop_table :pipelines
  end

  def down
    create_table :pipelines do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.timestamps
    end
    add_index :pipelines, [:user_id, :name]

    create_table :pipeline_books do |t|
      t.references :pipeline, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.integer :position, default: 0
      t.date :planned_start_date
      t.date :planned_end_date
      t.integer :track, default: 1
      t.timestamps
    end
    add_index :pipeline_books, [:pipeline_id, :book_id], unique: true
    add_index :pipeline_books, [:pipeline_id, :position]
    add_index :pipeline_books, :track
  end
end
