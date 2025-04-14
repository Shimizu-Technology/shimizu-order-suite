class CreateDefaultLocationsForExistingRestaurants < ActiveRecord::Migration[7.2]
  def up
    # Safety check - only run if the locations table exists
    return unless table_exists?(:locations) && table_exists?(:restaurants) && table_exists?(:orders)
    
    # Create a default location for each existing restaurant
    execute <<-SQL
      INSERT INTO locations (restaurant_id, name, address, phone_number, is_active, is_default, created_at, updated_at)
      SELECT id, 
             CONCAT(name, ' - Main Location'), 
             address, 
             phone_number, 
             TRUE, 
             TRUE, 
             NOW(), 
             NOW()
      FROM restaurants
    SQL
    
    # Update existing orders to use the default location for their restaurant
    execute <<-SQL
      UPDATE orders
      SET location_id = (
        SELECT l.id 
        FROM locations l 
        WHERE l.restaurant_id = orders.restaurant_id AND l.is_default = TRUE
        LIMIT 1
      )
      WHERE location_id IS NULL
    SQL
    
    # Now that all orders have a location, we can make the column not nullable
    change_column_null :orders, :location_id, false
  end
  
  def down
    # If we need to rollback, we'll make location_id nullable again
    change_column_null :orders, :location_id, true
    
    # We don't delete the created locations as that would break referential integrity
  end
end
