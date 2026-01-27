class CreatePipelines < ActiveRecord::Migration[7.1]
  def change
    create_table :pipelines do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    add_index :pipelines, [:user_id, :name]
  end
end
