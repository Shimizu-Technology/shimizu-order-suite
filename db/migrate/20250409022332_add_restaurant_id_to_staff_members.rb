class AddRestaurantIdToStaffMembers < ActiveRecord::Migration[7.2]
  def change
    # First add the column allowing nulls
    add_reference :staff_members, :restaurant, null: true, foreign_key: true
    
    # Add an index for better performance
    add_index :staff_members, :restaurant_id unless index_exists?(:staff_members, :restaurant_id)
    
    # Update existing staff members to associate with a restaurant
    # This assumes staff members are associated with users that have a restaurant_id
    execute <<-SQL
      UPDATE staff_members
      SET restaurant_id = users.restaurant_id
      FROM users
      WHERE staff_members.user_id = users.id
    SQL
    
    # After data migration, we can make the column non-nullable if needed
    # Commented out for now until we verify all data is properly migrated
    # change_column_null :staff_members, :restaurant_id, false
  end
end
