class CategorizeExistingMerchandiseItems < ActiveRecord::Migration[7.2]
  def up
    # Skip if the merchandise_categories table doesn't exist yet
    return unless table_exists?(:merchandise_categories)
    return unless table_exists?(:merchandise_items)
    
    # Get all restaurants with merchandise collections
    restaurants = execute("SELECT DISTINCT r.id, r.name FROM restaurants r 
                          JOIN merchandise_collections mc ON mc.restaurant_id = r.id").to_a
    
    restaurants.each do |restaurant|
      restaurant_id = restaurant['id']
      
      # Check if a General category already exists for this restaurant
      general_category = execute("SELECT id FROM merchandise_categories 
                              WHERE restaurant_id = #{restaurant_id} AND name = 'General' 
                              LIMIT 1").to_a
      
      category_id = nil
      
      if general_category.empty?
        # Create a default General category if it doesn't exist
        execute(<<~SQL)
          INSERT INTO merchandise_categories 
            (name, description, display_order, active, restaurant_id, created_at, updated_at)
          VALUES 
            ('General', 'Default category for merchandise items', 1, true, #{restaurant_id}, NOW(), NOW())
        SQL
        
        # Get the ID of the newly created category
        category_id = execute("SELECT id FROM merchandise_categories WHERE restaurant_id = #{restaurant_id} AND name = 'General' LIMIT 1").first['id']
      else
        # Use the existing General category
        category_id = general_category.first['id']
      end
      
      # Only update merchandise items that don't already have a category assigned
      execute(<<~SQL)
        UPDATE merchandise_items mi
        SET merchandise_category_id = #{category_id}
        FROM merchandise_collections mc
        WHERE mi.merchandise_collection_id = mc.id
        AND mc.restaurant_id = #{restaurant_id}
        AND mi.merchandise_category_id IS NULL
      SQL
    end
  end
  
  def down
    # Skip if the tables don't exist
    return unless table_exists?(:merchandise_categories)
    return unless table_exists?(:merchandise_items)
    
    # Remove category assignments from merchandise items that are assigned to General categories
    execute(<<~SQL)
      UPDATE merchandise_items mi
      SET merchandise_category_id = NULL
      FROM merchandise_categories mc
      WHERE mi.merchandise_category_id = mc.id
      AND mc.name = 'General'
    SQL
    
    # Delete all 'General' categories
    execute("DELETE FROM merchandise_categories WHERE name = 'General'")
  end
end
