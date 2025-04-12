class CreateRestaurantCounters < ActiveRecord::Migration[7.2]
  def change
    create_table :restaurant_counters do |t|
      t.references :restaurant, null: false, foreign_key: true, index: false
      t.integer :daily_order_counter, default: 0, null: false
      t.integer :total_order_counter, default: 0, null: false
      t.date :last_reset_date, null: false, default: -> { 'CURRENT_DATE' }

      t.timestamps
    end
    
    # Add a unique index to ensure only one counter per restaurant
    # Use unless_exists to prevent errors if the index already exists
    add_index :restaurant_counters, :restaurant_id, unique: true, if_not_exists: true
  end
end
