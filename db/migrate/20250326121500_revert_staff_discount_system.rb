class RevertStaffDiscountSystem < ActiveRecord::Migration[7.2]
  def up
    # First remove foreign key constraints
    if foreign_key_exists?(:staff_discounts, :staff_beneficiaries)
      remove_foreign_key :staff_discounts, :staff_beneficiaries
    end
    
    if foreign_key_exists?(:staff_discounts, :orders)
      remove_foreign_key :staff_discounts, :orders
    end
    
    if foreign_key_exists?(:staff_discounts, :users)
      remove_foreign_key :staff_discounts, :users
    end
    
    if foreign_key_exists?(:staff_beneficiaries, :restaurants)
      remove_foreign_key :staff_beneficiaries, :restaurants
    end
    
    # Drop tables
    drop_table :staff_discounts if table_exists?(:staff_discounts)
    drop_table :staff_beneficiaries if table_exists?(:staff_beneficiaries)
    
    # Remove house_account_balance column from users
    if column_exists?(:users, :house_account_balance)
      remove_column :users, :house_account_balance
    end
  end

  def down
    # Recreate staff_beneficiaries table
    create_table :staff_beneficiaries do |t|
      t.string :name, null: false
      t.bigint :restaurant_id, null: false
      t.boolean :active, default: true
      t.timestamps
      
      t.index [:restaurant_id, :name], unique: true
    end
    
    add_foreign_key :staff_beneficiaries, :restaurants
    
    # Recreate staff_discounts table
    create_table :staff_discounts do |t|
      t.references :order, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :staff_beneficiary, foreign_key: true
      t.decimal :discount_amount, precision: 10, scale: 2, null: false
      t.decimal :original_amount, precision: 10, scale: 2, null: false
      t.boolean :is_working, null: false
      t.string :payment_method, null: false
      t.boolean :is_paid, default: false
      t.datetime :paid_at
      t.timestamps
    end
    
    # Add house_account_balance column to users
    add_column :users, :house_account_balance, :decimal, precision: 10, scale: 2, default: 0.0
  end
end