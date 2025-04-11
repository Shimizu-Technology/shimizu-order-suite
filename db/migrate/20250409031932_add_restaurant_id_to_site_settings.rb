class AddRestaurantIdToSiteSettings < ActiveRecord::Migration[7.2]
  def up
    # First add the column as nullable
    add_reference :site_settings, :restaurant, null: true, foreign_key: true
    
    # Get the first restaurant to associate with existing records
    first_restaurant_id = Restaurant.first&.id
    
    if first_restaurant_id
      # Update existing records to associate with the first restaurant
      execute("UPDATE site_settings SET restaurant_id = #{first_restaurant_id}")
      
      # Now add the not-null constraint
      change_column_null :site_settings, :restaurant_id, false
    end
  end
  
  def down
    remove_reference :site_settings, :restaurant
  end
end
