class CreateTenantEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :tenant_events do |t|
      t.references :restaurant, null: false, foreign_key: { on_delete: :cascade }
      t.string :event_type, null: false
      t.jsonb :data, null: false, default: {}

      t.timestamps
    end
    
    # Add indexes for common queries
    add_index :tenant_events, [:restaurant_id, :event_type]
    add_index :tenant_events, [:restaurant_id, :created_at]
    add_index :tenant_events, :event_type
    
    # Add GIN index for JSON querying
    add_index :tenant_events, :data, using: :gin
    
    # Add check constraint to ensure event_type is not empty
    execute <<-SQL
      ALTER TABLE tenant_events
      ADD CONSTRAINT event_type_not_empty
      CHECK (event_type != '');
    SQL
  end
  
  def down
    drop_table :tenant_events
  end
end
