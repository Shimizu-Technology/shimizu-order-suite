class CreateVipAccessCodes < ActiveRecord::Migration[7.0]
  def change
    create_table :vip_access_codes do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.references :special_event, foreign_key: true, null: true # For future use
      t.string :code, null: false
      t.string :name
      t.integer :max_uses
      t.integer :current_uses, default: 0
      t.datetime :expires_at
      t.boolean :is_active, default: true
      t.references :user, foreign_key: true, null: true
      t.string :group_id
      
      t.timestamps
    end
    
    add_index :vip_access_codes, [:code, :restaurant_id], unique: true
  end
end
