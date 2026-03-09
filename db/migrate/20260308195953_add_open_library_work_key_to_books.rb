class AddOpenLibraryWorkKeyToBooks < ActiveRecord::Migration[7.1]
  def change
    add_column :books, :open_library_work_key, :string
  end
end
