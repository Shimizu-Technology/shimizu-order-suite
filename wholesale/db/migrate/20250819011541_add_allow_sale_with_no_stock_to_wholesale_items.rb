class AddAllowSaleWithNoStockToWholesaleItems < ActiveRecord::Migration[8.0]
  def change
    add_column :wholesale_items, :allow_sale_with_no_stock, :boolean, default: false, null: false
  end
end
