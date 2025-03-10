class AddLowStockThresholdToMerchandiseItems < ActiveRecord::Migration[7.2]
  def change
    # Only add the column if it doesn't already exist
    unless column_exists?(:merchandise_items, :low_stock_threshold)
      add_column :merchandise_items, :low_stock_threshold, :integer, default: 5
    end
  end
end
