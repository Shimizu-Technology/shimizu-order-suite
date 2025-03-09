class AddMerchandiseItemsToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :merchandise_items, :jsonb, default: []
  end
end
