# app/services/option_service.rb
class OptionService < TenantScopedService
  attr_accessor :current_user

  # Create a new option for an option group
  def create_option(option_group_id, option_params)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    
    option_group = find_option_group_with_tenant_scope(option_group_id)
    return { success: false, errors: ["Option group not found"], status: :not_found } unless option_group
    
    option = option_group.options.build(option_params)
    
    if option.save
      { success: true, option: option, status: :created }
    else
      { success: false, errors: option.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Update an existing option
  def update_option(id, option_params)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    
    option = find_option_with_tenant_scope(id)
    return { success: false, errors: ["Option not found"], status: :not_found } unless option
    
    if option.update(option_params)
      { success: true, option: option }
    else
      { success: false, errors: option.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Delete an option
  def delete_option(id)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    
    option = find_option_with_tenant_scope(id)
    return { success: false, errors: ["Option not found"], status: :not_found } unless option
    
    option.destroy
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

  # Find an option with tenant scoping
  def find_option_with_tenant_scope(id)
    # First find the option
    option = Option.find_by(id: id)
    return nil unless option
    
    # Then verify it belongs to an option group in the current restaurant
    option_group = option.option_group
    return nil unless option_group
    
    # Then verify it belongs to a menu item in the current restaurant
    menu_item = option_group.menu_item
    return nil unless menu_item
    
    # Verify the menu item belongs to a menu in the current restaurant
    menu = menu_item.menu
    return nil unless menu
    
    # Finally, check if the menu belongs to the current restaurant
    return option if menu.restaurant_id == current_restaurant.id
    
    nil
  end
end
