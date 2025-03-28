class AddCashFieldsToOrderPayments < ActiveRecord::Migration[7.2]
  def change
    add_column :order_payments, :cash_received, :decimal, precision: 10, scale: 2
    add_column :order_payments, :change_due, :decimal, precision: 10, scale: 2
  end
end
