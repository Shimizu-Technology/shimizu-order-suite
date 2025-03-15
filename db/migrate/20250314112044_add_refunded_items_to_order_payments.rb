class AddRefundedItemsToOrderPayments < ActiveRecord::Migration[7.2]
  def change
    add_column :order_payments, :refunded_items, :jsonb
  end
end
