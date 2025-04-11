# app/services/menu_service.rb
class MenuService < TenantScopedService
  attr_accessor :current_user

  # List all menus for the current restaurant
  def list_menus(params = {})
    scope_query(Menu).order(created_at: :asc)
  end

  # Find a specific menu by ID
  def find_menu(id)
    scope_query(Menu).find(id)
  end

  # Create a new menu
  def create_menu(menu_params)
    # Ensure the restaurant_id is set to the current restaurant
    menu_params = menu_params.merge(restaurant_id: @restaurant.id)
    menu = Menu.new(menu_params)
    
    if menu.save
      { success: true, menu: menu, status: :created }
    else
      { success: false, errors: menu.errors, status: :unprocessable_entity }
    end
  end

  # Update an existing menu
  def update_menu(id, menu_params)
    menu = scope_query(Menu).find(id)
    
    if menu.update(menu_params)
      { success: true, menu: menu }
    else
      { success: false, errors: menu.errors, status: :unprocessable_entity }
    end
  rescue ActiveRecord::RecordNotFound
    { success: false, errors: ["Menu not found"], status: :not_found }
  end

  # Delete a menu
  def delete_menu(id)
    menu = scope_query(Menu).find(id)
    
    # Check if this is the active menu
    if menu.restaurant&.current_menu_id == menu.id
      return { 
        success: false, 
        errors: ["Cannot delete the active menu. Please set another menu as active first."], 
        status: :unprocessable_entity 
      }
    end
    
    menu.destroy
    { success: true }
  rescue ActiveRecord::RecordNotFound
    { success: false, errors: ["Menu not found"], status: :not_found }
  end

  # Set a menu as active
  def set_active_menu(id)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless admin_user?
    
    begin
      menu = scope_query(Menu).find(id)
      
      # First update the menus in a transaction
      ActiveRecord::Base.transaction do
        # Set all menus for this restaurant to inactive
        scope_query(Menu).update_all(active: false)
        
        # Set the selected menu to active
        menu.update!(active: true)
      end
      
      # Now update the restaurant outside the transaction
      # This prevents the transaction from rolling back if there's an issue with the restaurant update
      begin
        # Use @restaurant from TenantScopedService instead of current_restaurant
        restaurant = Restaurant.find(@restaurant.id)
        restaurant.update_columns(current_menu_id: menu.id, updated_at: Time.current)
        
        # Log the successful menu activation
        Rails.logger.info("Menu #{menu.id} set as active for restaurant #{restaurant.id}")
        
        # Return success response
        return { 
          success: true, 
          message: "Menu set as active successfully",
          current_menu_id: menu.id
        }
      rescue => e
        Rails.logger.error("Failed to update restaurant with menu: #{e.message}")
        return { success: false, errors: ["Menu activated but failed to update restaurant: #{e.message}"], status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotFound
    { success: false, errors: ["Menu not found"], status: :not_found }
  rescue => e
    { success: false, errors: [e.message], status: :unprocessable_entity }
  end

  # Clone a menu
  def clone_menu(id)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless admin_user?
    
    original_menu = scope_query(Menu).find(id)
    
    new_menu = Menu.new(
      name: "#{original_menu.name} (Copy)",
      active: false,
      restaurant_id: @restaurant.id
    )
    
    if new_menu.save
      # Use a transaction to ensure all operations succeed or fail together
      ActiveRecord::Base.transaction do
        # Clone categories first
        category_mapping = {} # To map original category IDs to new category IDs
        
        original_menu.categories.each do |original_category|
          new_category = Category.create!(
            menu_id: new_menu.id,
            name: original_category.name,
            position: original_category.position,
            description: original_category.description
          )
          
          # Store the mapping from original to new category
          category_mapping[original_category.id] = new_category.id
        end

        # Clone all menu items
        original_menu.menu_items.each do |original_item|
          # Duplicate the menu item but don't save it yet
          new_item = original_item.dup
          new_item.menu_id = new_menu.id

          # Save without validation first to bypass the category validation temporarily
          new_item.save(validate: false)

          # Clone the category associations using the new categories
          original_item.menu_item_categories.each do |mic|
            # Use the new category ID from our mapping
            new_category_id = category_mapping[mic.category_id]
            
            MenuItemCategory.create!(
              menu_item_id: new_item.id,
              category_id: new_category_id
            )
          end

          # Now validate and save again to ensure all other validations pass
          new_item.validate!

          # Clone option groups and their options
          original_item.option_groups.each do |original_group|
            # Duplicate the option group
            new_group = original_group.dup
            new_group.menu_item_id = new_item.id
            new_group.save!

            # Clone options within the group
            original_group.options.each do |original_option|
              new_option = original_option.dup
              new_option.option_group_id = new_group.id
              new_option.save!
            end
          end
        end
      end
      
      { success: true, menu: new_menu, status: :created }
    else
      { success: false, errors: new_menu.errors.full_messages, status: :unprocessable_entity }
    end
  rescue ActiveRecord::RecordNotFound
    { success: false, errors: ["Menu not found"], status: :not_found }
  rescue => e
    { success: false, errors: [e.message], status: :unprocessable_entity }
  end

  private

  def admin_user?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
