class CreateStaffBeneficiaries < ActiveRecord::Migration[7.2]
  def change
    create_table :staff_beneficiaries do |t|
      t.string :name, null: false
      t.bigint :restaurant_id, null: false
      t.boolean :active, default: true
      t.timestamps
      
      t.index [:restaurant_id, :name], unique: true
    end
    
    add_foreign_key :staff_beneficiaries, :restaurants
  end
end
