class AddOnboardingFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :onboarding_completed_at, :datetime
    add_column :users, :yearly_book_goal, :integer

    reversible do |dir|
      dir.up do
        # Mark existing users as having completed onboarding so they aren't forced through it
        execute "UPDATE users SET onboarding_completed_at = created_at WHERE onboarding_completed_at IS NULL"
      end
    end
  end
end
