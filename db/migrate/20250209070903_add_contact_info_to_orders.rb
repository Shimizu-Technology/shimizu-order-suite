# db/migrate/20250210000000_add_contact_info_to_orders.rb

class AddContactInfoToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :contact_name, :string
    add_column :orders, :contact_phone, :string
    add_column :orders, :contact_email, :string
  end
end
