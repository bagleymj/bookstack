class AddPageRangeToBooks < ActiveRecord::Migration[7.1]
  def change
    add_column :books, :first_page, :integer, default: 1, null: false
    add_column :books, :last_page, :integer

    # Migrate existing data: set last_page from total_pages
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE books SET last_page = total_pages WHERE last_page IS NULL
        SQL
      end
    end

    change_column_null :books, :last_page, false
  end
end
