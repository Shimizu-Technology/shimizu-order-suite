class CreateWholesaleItemVariants < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_item_variants do |t|
      t.references :wholesale_item, null: false, foreign_key: { to_table: :wholesale_items }
      t.string :sku, null: false
      t.string :size
      t.string :color
      t.decimal :price_adjustment, precision: 8, scale: 2, default: 0.0
      t.integer :stock_quantity, default: 0
      t.integer :low_stock_threshold, default: 5
      t.integer :total_ordered, default: 0
      t.decimal :total_revenue, precision: 10, scale: 2, default: 0.0
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :wholesale_item_variants, :sku, unique: true
    add_index :wholesale_item_variants, [:wholesale_item_id, :size, :color], unique: true, name: 'index_wholesale_variants_on_item_size_color'
  end
end
