class AddInventoryTrackingToOptions < ActiveRecord::Migration[7.2]
  def change
    add_column :options, :enable_stock_tracking, :boolean, default: false
    add_column :options, :stock_quantity, :integer, default: 0
    add_column :options, :damaged_quantity, :integer, default: 0
    add_column :options, :low_stock_threshold, :integer
    add_column :options, :stock_status, :integer, default: 0
    
    # Add index for performance
    add_index :options, :stock_status
  end
end