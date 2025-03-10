class AddCostToMakeToMenuItems < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_items, :cost_to_make, :decimal, precision: 8, scale: 2, default: 0.0
  end
end
