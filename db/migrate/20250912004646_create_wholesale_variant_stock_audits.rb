class CreateWholesaleVariantStockAudits < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_variant_stock_audits do |t|
      # Reference to the variant being audited
      t.references :wholesale_item_variant, null: false, foreign_key: { to_table: :wholesale_item_variants }
      
      # Type of audit event
      t.string :audit_type, null: false
      
      # Quantity changes
      t.integer :quantity_change, null: false, default: 0
      t.integer :previous_quantity, null: false, default: 0
      t.integer :new_quantity, null: false, default: 0
      
      # Reason for the change
      t.text :reason
      
      # Who made the change (optional for system changes)
      t.references :user, null: true, foreign_key: true
      
      # Associated order (for order-related changes)
      t.references :order, null: true, foreign_key: { to_table: :wholesale_orders }
      
      # Additional metadata
      t.json :metadata, default: {}
      
      t.timestamps
    end
    
    # Indexes for efficient querying
    add_index :wholesale_variant_stock_audits, :audit_type
    add_index :wholesale_variant_stock_audits, :created_at
    add_index :wholesale_variant_stock_audits, [:wholesale_item_variant_id, :created_at], name: 'index_variant_audits_on_variant_and_created_at'
    add_index :wholesale_variant_stock_audits, [:user_id, :created_at], name: 'index_variant_audits_on_user_and_created_at'
    add_index :wholesale_variant_stock_audits, [:order_id, :created_at], name: 'index_variant_audits_on_order_and_created_at'
  end
end