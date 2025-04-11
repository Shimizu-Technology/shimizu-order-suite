class CreateAuditLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :audit_logs do |t|
      t.integer :restaurant_id, null: false
      t.integer :user_id
      t.string :action, null: false
      t.string :resource_type
      t.integer :resource_id
      t.jsonb :details, default: {}
      t.string :ip_address

      t.timestamps
    end
    
    # Add indexes for efficient querying
    add_index :audit_logs, :restaurant_id
    add_index :audit_logs, :user_id
    add_index :audit_logs, :action
    add_index :audit_logs, [:resource_type, :resource_id]
    add_index :audit_logs, :created_at
    
    # Add index for JSONB querying
    add_index :audit_logs, :details, using: :gin
    
    # Add foreign key constraint
    add_foreign_key :audit_logs, :restaurants, on_delete: :cascade
  end
end
