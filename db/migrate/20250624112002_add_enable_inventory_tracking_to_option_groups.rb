class AddEnableInventoryTrackingToOptionGroups < ActiveRecord::Migration[7.2]
  def change
    add_column :option_groups, :enable_inventory_tracking, :boolean, default: false, null: false
  end
end
