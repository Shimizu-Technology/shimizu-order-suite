class AddStockStatusAndNoteToMenuItems < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_items, :stock_status, :integer
    add_column :menu_items, :status_note, :text
  end
end
