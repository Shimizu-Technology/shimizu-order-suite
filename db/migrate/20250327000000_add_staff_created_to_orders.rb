class AddStaffCreatedToOrders < ActiveRecord::Migration[6.1]
  def change
    add_column :orders, :staff_created, :boolean, default: false
  end
end