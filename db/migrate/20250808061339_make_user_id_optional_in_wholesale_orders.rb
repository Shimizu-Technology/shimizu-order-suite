class MakeUserIdOptionalInWholesaleOrders < ActiveRecord::Migration[7.2]
  def change
    change_column_null :wholesale_orders, :user_id, true
  end
end
