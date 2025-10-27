class AddPageNumbersToBooks < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :first_page, :integer
    add_column :books, :last_page, :integer
  end
end
