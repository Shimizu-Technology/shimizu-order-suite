class CreateStoreCredits < ActiveRecord::Migration[6.1]
  def change
    create_table :store_credits do |t|
      t.references :order, null: true
      t.string :customer_email, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :reason
      t.string :status, default: 'active'
      t.datetime :expires_at
      t.decimal :remaining_amount, precision: 10, scale: 2
      
      t.timestamps
    end
    
    add_index :store_credits, :customer_email
    add_index :store_credits, :status
  end
end
