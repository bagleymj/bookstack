class AddHeijunkaFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :concurrency_limit, :integer
    add_column :users, :quotas_generated_on, :date
  end
end
