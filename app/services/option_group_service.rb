# app/services/option_group_service.rb
class OptionGroupService < TenantScopedService
  attr_accessor :current_user

  # List all option groups for a menu item
  def list_option_groups(menu_item_id)
    menu_item = scope_query(MenuItem).find_by(id: menu_item_id)
    return [] unless menu_item
    
    menu_item.option_groups.includes(:options)
  end

  # Create a new option group for a menu item
  def create_option_group(menu_item_id, option_group_params)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    
    menu_item = scope_query(MenuItem).find_by(id: menu_item_id)
    return { success: false, errors: ["Menu item not found"], status: :not_found } unless menu_item
    
    option_group = menu_item.option_groups.build(option_group_params)
    
    if option_group.save
      { success: true, option_group: option_group, status: :created }
    else
      { success: false, errors: option_group.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Update an existing option group
  def update_option_group(id, option_group_params)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    
    option_group = find_option_group_with_tenant_scope(id)
    return { success: false, errors: ["Option group not found"], status: :not_found } unless option_group
    
    if option_group.update(option_group_params)
      { success: true, option_group: option_group }
    else
      { success: false, errors: option_group.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Delete an option group
  def delete_option_group(id)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    
    option_group = find_option_group_with_tenant_scope(id)
    return { success: false, errors: ["Option group not found"], status: :not_found } unless option_group
    
    option_group.destroy
    { success: true }
  end

  private

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end

  # Find an option group with tenant scoping
  def find_option_group_with_tenant_scope(id)
    # First find the option group
    option_group = OptionGroup.find_by(id: id)
    return nil unless option_group
    
    # Then verify it belongs to a menu item in the current restaurant
    menu_item = option_group.menu_item
    return nil unless menu_item
    
    # Verify the menu item belongs to a menu in the current restaurant
    menu = menu_item.menu
    return nil unless menu
    
    # Finally, check if the menu belongs to the current restaurant
    return option_group if menu.restaurant_id == current_restaurant.id
    
    nil
  end
end
