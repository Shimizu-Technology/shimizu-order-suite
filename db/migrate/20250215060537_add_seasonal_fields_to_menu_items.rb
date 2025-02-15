class AddSeasonalFieldsToMenuItems < ActiveRecord::Migration[7.0]
  def change
    add_column :menu_items, :seasonal, :boolean, default: false, null: false
    add_column :menu_items, :available_from, :date
    add_column :menu_items, :available_until, :date
  end
end
