class AddStaffOrderFieldsToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :is_staff_order, :boolean, default: false
    add_column :orders, :staff_member_id, :bigint
    add_column :orders, :staff_on_duty, :boolean, default: false
    add_column :orders, :use_house_account, :boolean, default: false
    add_column :orders, :created_by_staff_id, :bigint
    add_column :orders, :pre_discount_total, :decimal, precision: 10, scale: 2
    
    # Add indices for faster lookups
    add_index :orders, :is_staff_order
    add_index :orders, :staff_member_id
    add_index :orders, :created_by_staff_id
    add_index :orders, [:is_staff_order, :use_house_account], name: 'index_orders_on_staff_order_and_house_account'
    
    # Add foreign key constraint for staff_member_id
    add_foreign_key :orders, :staff_members, column: :staff_member_id, on_delete: :nullify
    add_foreign_key :orders, :staff_members, column: :created_by_staff_id, on_delete: :nullify
  end
end
