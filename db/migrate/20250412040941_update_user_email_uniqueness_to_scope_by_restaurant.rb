class UpdateUserEmailUniquenessToScopeByRestaurant < ActiveRecord::Migration[7.2]
  def up
    # First, remove the existing unique index on email
    # Using execute to handle the functional index on lower(email)
    execute <<-SQL
      DROP INDEX IF EXISTS index_users_on_lower_email;
    SQL
    
    # Add a new composite unique index on email and restaurant_id
    # This allows the same email to be used across different restaurants
    # while maintaining uniqueness within each restaurant
    execute <<-SQL
      CREATE UNIQUE INDEX index_users_on_lower_email_and_restaurant_id 
      ON users (lower(email), COALESCE(restaurant_id, 0));
      
      COMMENT ON INDEX index_users_on_lower_email_and_restaurant_id IS 
      'Ensures email uniqueness within each restaurant, with special handling for super_admins';
    SQL
  end
  
  def down
    # Remove the composite index using execute to handle the functional index
    execute <<-SQL
      DROP INDEX IF EXISTS index_users_on_lower_email_and_restaurant_id;
    SQL
    
    # Restore the original unique index on email
    # Note: This might fail if there are now duplicate emails across restaurants
    execute <<-SQL
      CREATE UNIQUE INDEX IF NOT EXISTS index_users_on_lower_email 
      ON users (lower(email));
    SQL
  end
end
