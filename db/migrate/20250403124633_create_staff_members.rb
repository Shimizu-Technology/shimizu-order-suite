class CreateStaffMembers < ActiveRecord::Migration[7.2]
  def change
    create_table :staff_members do |t|
      t.string :name, null: false
      t.string :position
      t.bigint :user_id
      t.decimal :house_account_balance, precision: 10, scale: 2, default: 0.0, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    # Add index for user_id for faster lookups
    add_index :staff_members, :user_id, unique: true, where: "user_id IS NOT NULL"
    # Add index for active status for filtering
    add_index :staff_members, :active
  end
end
