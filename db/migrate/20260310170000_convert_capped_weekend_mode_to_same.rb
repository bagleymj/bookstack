class ConvertCappedWeekendModeToSame < ActiveRecord::Migration[7.1]
  def up
    # Convert any users with capped (2) weekend mode to same (1)
    execute "UPDATE users SET weekend_mode = 1 WHERE weekend_mode = 2"
  end

  def down
    # No-op: can't restore which users were previously capped
  end
end
