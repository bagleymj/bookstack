class RenameDifficultyToDensity < ActiveRecord::Migration[7.1]
  def change
    rename_column :books, :difficulty, :density
    rename_column :books, :actual_difficulty_modifier, :actual_density_modifier
  end
end
