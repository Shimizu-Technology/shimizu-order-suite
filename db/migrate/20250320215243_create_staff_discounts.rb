class CreateStaffDiscounts < ActiveRecord::Migration[7.2]
  def change
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
  end
end
