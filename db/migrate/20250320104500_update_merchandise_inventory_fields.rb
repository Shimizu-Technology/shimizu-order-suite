class UpdateMerchandiseInventoryFields < ActiveRecord::Migration[6.1]
  def change
    # Add enable_inventory_tracking to merchandise_items if it doesn't exist
    unless column_exists?(:merchandise_items, :enable_inventory_tracking)
      add_column :merchandise_items, :enable_inventory_tracking, :boolean, default: false
    end

    # Add damaged_quantity to merchandise_variants if it doesn't exist
    unless column_exists?(:merchandise_variants, :damaged_quantity)
      add_column :merchandise_variants, :damaged_quantity, :integer, default: 0
    end

    # Add low_stock_threshold to merchandise_variants if it doesn't exist
    unless column_exists?(:merchandise_variants, :low_stock_threshold)
      add_column :merchandise_variants, :low_stock_threshold, :integer, default: 5
    end
  end
end
