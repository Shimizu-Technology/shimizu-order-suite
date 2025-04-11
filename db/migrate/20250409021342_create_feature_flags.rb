class CreateFeatureFlags < ActiveRecord::Migration[7.2]
  def change
    create_table :feature_flags do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :enabled, null: false, default: false
      t.boolean :global, null: false, default: false
      t.integer :restaurant_id
      t.jsonb :configuration, default: {}

      t.timestamps
    end
    
    # Add indexes for efficient querying
    add_index :feature_flags, :name
    add_index :feature_flags, :restaurant_id
    add_index :feature_flags, :global
    add_index :feature_flags, [:name, :restaurant_id], unique: true
    add_index :feature_flags, :configuration, using: :gin
    
    # Add foreign key constraint for restaurant_id
    add_foreign_key :feature_flags, :restaurants, on_delete: :cascade
  end
end
