class MigrateCategoryAssociations < ActiveRecord::Migration[7.2]
  def up
    # For each restaurant
    Restaurant.find_each do |restaurant|
      # Get all categories for this restaurant
      restaurant_categories = Category.where(restaurant_id: restaurant.id)
      
      # For each menu in the restaurant
      restaurant.menus.find_each do |menu|
        # Duplicate each category for this menu
        restaurant_categories.each do |category|
          # Create a duplicate category for this menu
          menu_category = Category.create!(
            name: category.name,
            position: category.position,
            description: category.description,
            restaurant_id: restaurant.id, # Keep restaurant_id for now
            menu_id: menu.id # Associate with this menu
          )
          
          # Update menu_item_categories for menu items in this menu
          menu.menu_items.joins(:menu_item_categories)
                         .where(menu_item_categories: { category_id: category.id })
                         .find_each do |menu_item|
            # Create new menu_item_category associations with the new menu-specific category
            MenuItemCategory.create!(
              menu_item_id: menu_item.id,
              category_id: menu_category.id
            )
          end
        end
      end
      
      # After creating duplicates for all menus, delete the original categories
      # This is safe because we've created duplicates and updated all associations
      restaurant_categories.destroy_all
    end
    
    # Handle any remaining categories without a menu_id
    # This is a safety measure in case there are any categories not associated with a restaurant
    remaining_categories = Category.where(menu_id: nil)
    if remaining_categories.exists?
      # Find a default menu to associate these categories with
      default_menu = Menu.first
      
      if default_menu
        remaining_categories.update_all(menu_id: default_menu.id)
      else
        # If there's no menu at all, we need to create one
        if Restaurant.exists?
          default_restaurant = Restaurant.first
          default_menu = Menu.create!(name: "Default Menu", restaurant_id: default_restaurant.id)
          remaining_categories.update_all(menu_id: default_menu.id)
        else
          # If there are no restaurants, we can't proceed
          raise "Cannot migrate categories: No restaurants found in the database"
        end
      end
    end
  end

  def down
    # This migration is not easily reversible without data loss
    raise ActiveRecord::IrreversibleMigration
  end
end
