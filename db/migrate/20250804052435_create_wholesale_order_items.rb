class CreateWholesaleOrderItems < ActiveRecord::Migration[7.2]
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
    
    # Note: order_id and item_id indexes are automatically created by foreign key references
  end
end
