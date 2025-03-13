class AddPaymentFieldsForStripeWebhooks < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :refund_amount, :decimal, precision: 10, scale: 2
    add_column :orders, :dispute_reason, :string
    add_column :orders, :payment_id, :string
    
    # Add an index to make lookups by payment_id faster
    add_index :orders, :payment_id
  end
end
