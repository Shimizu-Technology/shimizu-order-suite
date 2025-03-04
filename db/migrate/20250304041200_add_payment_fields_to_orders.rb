class AddPaymentFieldsToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :payment_method, :string
    add_column :orders, :transaction_id, :string
    add_column :orders, :payment_status, :string, default: 'pending'
    add_column :orders, :payment_amount, :decimal, precision: 10, scale: 2
  end
end
