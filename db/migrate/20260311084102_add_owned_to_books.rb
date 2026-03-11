class AddOwnedToBooks < ActiveRecord::Migration[7.1]
  def up
    add_column :books, :owned, :boolean, default: false, null: false
    Book.update_all(owned: true)
  end

  def down
    remove_column :books, :owned
  end
end
