class AddInventoryFieldsToOptions < ActiveRecord::Migration[7.2]
  def change
    # Add inventory tracking fields to options table if they don't exist
    unless column_exists?(:options, :damaged_quantity)
      add_column :options, :damaged_quantity, :integer, default: 0
    end
    
    unless column_exists?(:options, :low_stock_threshold)
      add_column :options, :low_stock_threshold, :integer
    end
    
    # Make sure other inventory fields exist
    unless column_exists?(:options, :enable_stock_tracking)
      add_column :options, :enable_stock_tracking, :boolean, default: false
    end
    
    unless column_exists?(:options, :stock_quantity)
      add_column :options, :stock_quantity, :integer, default: 0
    end
    
    unless column_exists?(:options, :stock_status)
      add_column :options, :stock_status, :integer, default: 0
    end
    
    # Add index for performance if it doesn't exist
    unless index_exists?(:options, :stock_status)
      add_index :options, :stock_status
    end
  end
end