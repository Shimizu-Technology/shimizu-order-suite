class UpdateWholesaleItemVariantsForFlexibleTracking < ActiveRecord::Migration[7.2]
  def change
    # Add new columns for flexible variant tracking
    add_column :wholesale_item_variants, :variant_key, :string
    add_column :wholesale_item_variants, :variant_name, :string
    add_column :wholesale_item_variants, :damaged_quantity, :integer, default: 0, null: false
    
    # Remove the unique constraint on SKU since we'll make it optional
    remove_index :wholesale_item_variants, :sku
    
    # Remove the unique constraint on item/size/color since we're moving to flexible keys
    remove_index :wholesale_item_variants, name: 'index_wholesale_variants_on_item_size_color'
    
    # Make SKU optional (it was required before)
    change_column_null :wholesale_item_variants, :sku, true
    
    # Add new indexes for the flexible system
    add_index :wholesale_item_variants, [:wholesale_item_id, :variant_key], unique: true, name: 'index_wholesale_variants_on_item_and_key'
    add_index :wholesale_item_variants, :variant_key
    add_index :wholesale_item_variants, :stock_quantity
    add_index :wholesale_item_variants, [:stock_quantity, :damaged_quantity]
    
    # Add track_variants field to wholesale_items table
    add_column :wholesale_items, :track_variants, :boolean, default: false, null: false
    add_index :wholesale_items, :track_variants
  end
end