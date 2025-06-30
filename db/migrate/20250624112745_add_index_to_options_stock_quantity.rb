class AddIndexToOptionsStockQuantity < ActiveRecord::Migration[7.2]
  def change
    add_index :options, :stock_quantity
  end
end
