class RemoveOpenLibraryWorkKeyFromBooks < ActiveRecord::Migration[7.1]
  def change
    remove_column :books, :open_library_work_key, :string
  end
end
