class FixRestaurantCounterUniqueIndex < ActiveRecord::Migration[7.0]
  def change
    # Remove the old unique index on restaurant_id if it exists
    if index_exists?(:restaurant_counters, :restaurant_id, unique: true, name: "index_restaurant_counters_on_restaurant_id")
      remove_index :restaurant_counters, name: "index_restaurant_counters_on_restaurant_id"
    end

    # Add (or ensure) the unique index on [restaurant_id, location_id]
    unless index_exists?(:restaurant_counters, [:restaurant_id, :location_id], unique: true, name: "index_restaurant_counters_on_restaurant_id_and_location_id")
      add_index :restaurant_counters, [:restaurant_id, :location_id], unique: true, name: "index_restaurant_counters_on_restaurant_id_and_location_id"
    end
  end
end