class AddUntrackedToReadingSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :reading_sessions, :untracked, :boolean, default: false, null: false
  end
end
