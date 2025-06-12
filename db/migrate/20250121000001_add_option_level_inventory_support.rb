class AddOptionLevelInventorySupport < ActiveRecord::Migration[7.2]
  def change
    # Add option inventory tracking fields to option_groups
    add_column :option_groups, :enable_option_inventory, :boolean, default: false, null: false
    add_column :option_groups, :low_stock_threshold, :integer, default: 10, null: false
    add_column :option_groups, :tracking_priority, :integer, default: 0, null: false
    
    # Add stock tracking fields to options
    add_column :options, :stock_quantity, :integer, default: 0, null: false
    add_column :options, :damaged_quantity, :integer, default: 0, null: false
    
    # Create unique index to ensure only one primary tracking group per menu item
    # This allows tracking_priority = 1 for only one option group per menu item
    add_index :option_groups, [:menu_item_id, :tracking_priority], 
              unique: true, 
              where: "tracking_priority = 1",
              name: "idx_option_groups_primary_tracking"
    
    # Add regular indexes for performance
    add_index :option_groups, :enable_option_inventory
    add_index :option_groups, :tracking_priority
    add_index :options, :stock_quantity
  end
end 