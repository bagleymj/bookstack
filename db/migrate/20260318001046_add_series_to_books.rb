class AddSeriesToBooks < ActiveRecord::Migration[7.1]
  def change
    add_column :books, :series_name, :string
    add_column :books, :series_position, :integer
    add_index :books, [:user_id, :series_name], where: "series_name IS NOT NULL"
  end
end
