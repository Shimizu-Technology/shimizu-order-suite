class AddStaffDiscountConfigurationToOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :orders, :staff_discount_configuration, foreign_key: true, null: true, index: true
  end
end 