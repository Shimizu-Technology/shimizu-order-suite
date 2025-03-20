class AddHiddenToMenuItems < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_items, :hidden, :boolean, default: false, null: false
  end
end
