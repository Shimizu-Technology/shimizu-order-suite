class AddLowStockThresholdToMenuItems < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_items, :low_stock_threshold, :integer, default: 10
  end
end
