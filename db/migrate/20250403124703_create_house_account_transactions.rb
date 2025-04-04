class CreateHouseAccountTransactions < ActiveRecord::Migration[7.2]
  def change
    create_table :house_account_transactions do |t|
      t.bigint :staff_member_id, null: false
      t.bigint :order_id
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :transaction_type, null: false
      t.string :description
      t.string :reference
      t.bigint :created_by_id

      t.timestamps
    end

    # Add foreign key constraints
    add_foreign_key :house_account_transactions, :staff_members
    add_foreign_key :house_account_transactions, :orders, on_delete: :nullify
    
    # Add indices for faster lookups
    add_index :house_account_transactions, :staff_member_id
    add_index :house_account_transactions, :order_id
    add_index :house_account_transactions, :created_by_id
    add_index :house_account_transactions, :transaction_type
  end
end
