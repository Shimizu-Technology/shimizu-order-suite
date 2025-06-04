class CreateFundraiserCounters < ActiveRecord::Migration[7.0]
  def change
    create_table :fundraiser_counters do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.references :fundraiser, null: false, foreign_key: true
      t.integer :counter_value, null: false, default: 0
      
      t.timestamps
    end
    
    add_index :fundraiser_counters, [:restaurant_id, :fundraiser_id], unique: true
  end
end
