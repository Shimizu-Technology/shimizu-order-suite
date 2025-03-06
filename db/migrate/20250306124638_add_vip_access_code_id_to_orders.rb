class AddVipAccessCodeIdToOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :orders, :vip_access_code, null: true, foreign_key: true
  end
end
