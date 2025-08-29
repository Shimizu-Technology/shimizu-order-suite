class CreateWholesaleItemStockAudits < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_item_stock_audits do |t|
      t.references :wholesale_item, null: false, foreign_key: { to_table: :wholesale_items }
      t.string :audit_type, null: false # 'stock_update', 'damaged', 'order_placed', 'order_cancelled', etc.
      t.integer :quantity_change # Can be positive or negative
      t.integer :previous_quantity
      t.integer :new_quantity
      t.text :reason
      t.references :user, null: true, foreign_key: true # Nullable for system actions
      t.references :order, null: true, foreign_key: { to_table: :wholesale_orders } # Nullable for manual adjustments

      t.timestamps
    end
    
    # Add indexes for performance
    add_index :wholesale_item_stock_audits, :audit_type
    add_index :wholesale_item_stock_audits, :created_at
    add_index :wholesale_item_stock_audits, [:wholesale_item_id, :created_at]
  end
end
