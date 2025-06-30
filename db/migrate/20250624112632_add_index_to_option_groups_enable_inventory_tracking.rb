class AddIndexToOptionGroupsEnableInventoryTracking < ActiveRecord::Migration[7.2]
  def change
    add_index :option_groups, :enable_inventory_tracking
  end
end
