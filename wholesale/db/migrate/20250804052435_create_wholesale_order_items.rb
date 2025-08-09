class CreateWholesaleOrderItems < ActiveRecord::Migration[8.0]
  def change
    create_table :wholesale_order_items do |t|
      t.references :order, null: false, foreign_key: { to_table: :wholesale_orders }
      t.references :item, null: false, foreign_key: { to_table: :wholesale_items }
      t.integer :quantity, null: false
      t.integer :price_cents, null: false
      
      # Snapshot fields for data integrity
      t.string :item_name
      t.text :item_description
      
      t.timestamps
    end
    
    # Indexes for performance
    add_index :wholesale_order_items, [:order_id]
    add_index :wholesale_order_items, [:item_id]
  end
end
