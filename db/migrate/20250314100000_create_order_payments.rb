class CreateOrderPayments < ActiveRecord::Migration[7.2]
  def change
    create_table :order_payments do |t|
      t.references :order, null: false, foreign_key: true
      t.string :payment_type, null: false # 'initial', 'additional', 'refund'
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :payment_method # 'stripe', 'paypal', etc.
      t.string :transaction_id
      t.string :payment_id
      t.jsonb :payment_details
      t.string :status
      t.string :description # e.g., "Additional items", "Partial refund"
      
      t.timestamps
    end
    
    add_index :order_payments, :transaction_id
    add_index :order_payments, :payment_id
  end
end
