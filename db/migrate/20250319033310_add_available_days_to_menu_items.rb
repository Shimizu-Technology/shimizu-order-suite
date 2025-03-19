class AddAvailableDaysToMenuItems < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_items, :available_days, :jsonb, default: []
  end
end
