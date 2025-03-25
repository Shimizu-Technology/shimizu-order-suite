class EnsureCategoriesHaveMenuId < ActiveRecord::Migration[7.2]
  def up
    # Find categories with null menu_id
    categories_without_menu = Category.where(menu_id: nil)
    
    if categories_without_menu.exists?
      puts "Found #{categories_without_menu.count} categories without a menu_id"
      
      # Find a default menu to associate these categories with
      default_menu = Menu.first
      
      if default_menu
        puts "Associating categories with menu: #{default_menu.name} (ID: #{default_menu.id})"
        
        # Handle each category individually to avoid unique constraint violations
        categories_without_menu.each do |category|
          # Check if a category with the same name already exists in this menu
          existing_category = Category.where(menu_id: default_menu.id, name: category.name).first
          
          if existing_category
            puts "Category '#{category.name}' already exists in menu #{default_menu.id}, deleting the duplicate"
            # If a category with this name already exists in the menu, we can safely delete this one
            # since it's likely a duplicate that wasn't properly handled in the previous migration
            category.destroy
          else
            # If no category with this name exists in the menu, update this one
            puts "Updating category '#{category.name}' to belong to menu #{default_menu.id}"
            category.update_column(:menu_id, default_menu.id)
          end
        end
      else
        # If there's no menu at all, we need to create one
        if Restaurant.exists?
          default_restaurant = Restaurant.first
          puts "Creating a default menu for restaurant: #{default_restaurant.name} (ID: #{default_restaurant.id})"
          default_menu = Menu.create!(name: "Default Menu", restaurant_id: default_restaurant.id)
          
          # Handle each category individually
          categories_without_menu.each do |category|
            puts "Updating category '#{category.name}' to belong to the new menu #{default_menu.id}"
            category.update_column(:menu_id, default_menu.id)
          end
        else
          # If there are no restaurants, we can't proceed
          raise "Cannot migrate categories: No restaurants found in the database"
        end
      end
      
      # Verify all categories now have a menu_id
      remaining_null = Category.where(menu_id: nil).count
      if remaining_null > 0
        raise "Failed to update all categories. #{remaining_null} categories still have null menu_id."
      else
        puts "Successfully updated all categories to have a menu_id"
      end
    else
      puts "No categories found with null menu_id. Nothing to do."
    end
  end

  def down
    # This migration doesn't need to be reversed
    # If we were to reverse it, we'd set menu_id back to null for some categories,
    # but that's not necessary or desirable
  end
end