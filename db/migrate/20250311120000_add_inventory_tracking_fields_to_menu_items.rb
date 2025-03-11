class AddInventoryTrackingFieldsToMenuItems < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_items, :enable_stock_tracking, :boolean, default: false
    add_column :menu_items, :stock_quantity, :integer
    add_column :menu_items, :damaged_quantity, :integer, default: 0
  end
end
