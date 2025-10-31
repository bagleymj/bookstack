class CreateReadthroughs < ActiveRecord::Migration[8.0]
  def change
    create_table :readthroughs do |t|
      t.references :user_book, null: false, foreign_key: true
      t.date :start_date
      t.date :end_date

      t.timestamps
    end
  end
end
