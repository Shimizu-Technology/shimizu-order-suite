class CreateWholesaleOrderPayments < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_order_payments do |t|
      t.references :order, null: false, foreign_key: { to_table: :wholesale_orders }
      t.integer :amount_cents, null: false
      t.string :payment_method, default: 'stripe'
      t.string :status, default: 'pending'
      
      # Stripe-specific fields
      t.string :stripe_payment_intent_id
      t.string :stripe_charge_id
      t.string :transaction_id
      t.jsonb :payment_data, default: {}
      t.timestamp :processed_at
      
      t.timestamps
    end
    
    # Indexes for performance and lookups
    # Note: order_id index is automatically created by foreign key reference
    add_index :wholesale_order_payments, [:status]
    add_index :wholesale_order_payments, [:stripe_payment_intent_id]
  end
end
