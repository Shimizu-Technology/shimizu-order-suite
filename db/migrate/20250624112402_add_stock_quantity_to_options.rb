class AddStockQuantityToOptions < ActiveRecord::Migration[7.2]
  def change
    add_column :options, :stock_quantity, :integer, default: 0
  end
end
