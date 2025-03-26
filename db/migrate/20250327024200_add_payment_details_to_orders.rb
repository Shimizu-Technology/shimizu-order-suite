class AddPaymentDetailsToOrders < ActiveRecord::Migration[7.0]
  def change
    add_column :orders, :payment_details, :jsonb
  end
end