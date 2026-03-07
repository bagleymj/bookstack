class AddCompletedAtToBooks < ActiveRecord::Migration[7.1]
  def up
    add_column :books, :completed_at, :datetime
    execute "UPDATE books SET completed_at = updated_at WHERE status = 2"
  end

  def down
    remove_column :books, :completed_at
  end
end
