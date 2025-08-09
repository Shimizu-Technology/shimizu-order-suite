class CreateWholesaleItems < ActiveRecord::Migration[8.0]
  def change
    create_table :wholesale_items do |t|
      t.references :fundraiser, null: false, foreign_key: { to_table: :wholesale_fundraisers }
      t.string :name, null: false
      t.text :description
      t.string :sku
      t.integer :price_cents, null: false
      
      # Inventory tracking fields (future-ready)
      t.integer :stock_quantity              # nil = unlimited
      t.integer :low_stock_threshold        # when to alert
      t.boolean :track_inventory, default: false
      
      # Admin management fields
      t.integer :position, default: 0
      t.integer :sort_order, default: 0
      t.boolean :active, default: true
      t.jsonb :options, default: {}          # sizes, colors, etc.
      t.text :admin_notes                   # internal notes
      t.timestamp :last_restocked_at        # inventory tracking
      
      t.timestamps
    end
    
    # Indexes for performance
    add_index :wholesale_items, [:fundraiser_id, :active]
    add_index :wholesale_items, [:fundraiser_id, :sort_order]
    add_index :wholesale_items, [:track_inventory, :stock_quantity]
  end
end
