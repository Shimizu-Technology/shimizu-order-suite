class AddVipCodeToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :vip_code, :string
  end
end
