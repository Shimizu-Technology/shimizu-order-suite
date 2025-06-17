class AddLocationIDtoResaurantCounters < ActiveRecord::Migration[7.2]
  def change
    #add location_id to restaurant_counters table
    add_reference :restaurant_counters, :location, null: true, foreign_key: true
    #ensures that restaurant counter is unique for each location (CPK Agana)
    add_index :restaurant_counters, [:restaurant_id, :location_id], unique: true
  end
end
