class AddEstimatedDurationToReadingSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :reading_sessions, :estimated_duration_seconds, :integer
    add_column :reading_sessions, :wpm_snapshot, :float
  end
end
