class CreateWholesaleOrders < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_orders do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.references :fundraiser, null: false, foreign_key: { to_table: :wholesale_fundraisers }
      t.references :user, null: false, foreign_key: true
      t.references :participant, null: true, foreign_key: { to_table: :wholesale_participants }
      
      t.string :order_number, null: false
      t.string :customer_name, null: false
      t.string :customer_email, null: false
      t.string :customer_phone
      t.text :shipping_address
      t.integer :total_cents, null: false
      t.string :status, default: 'pending'
      t.text :notes
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    # Indexes for performance and uniqueness
    add_index :wholesale_orders, [:restaurant_id, :order_number], unique: true
    add_index :wholesale_orders, [:restaurant_id, :status]
    add_index :wholesale_orders, [:fundraiser_id, :status]
    # Note: participant_id index is automatically created by the foreign key reference
  end
end
