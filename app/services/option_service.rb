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

  # Batch update multiple options
  def batch_update_options(option_ids, updates)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    return { success: false, errors: ["No options selected"], status: :unprocessable_entity } if option_ids.blank?
    return { success: false, errors: ["No updates specified"], status: :unprocessable_entity } if updates.blank?
    
    # Find all options with tenant scoping
    valid_options = []
    option_ids.each do |id|
      option = find_option_with_tenant_scope(id)
      valid_options << option if option
    end
    
    return { success: false, errors: ["No valid options found"], status: :not_found } if valid_options.empty?
    
    # Update all valid options
    updated_count = 0
    valid_options.each do |option|
      if option.update(updates)
        updated_count += 1
      end
    end
    
    if updated_count > 0
      { success: true, updated_count: updated_count }
    else
      { success: false, errors: ["Failed to update options"], status: :unprocessable_entity }
    end
  end

  # Batch update positions for multiple options
  def batch_update_positions(positions_data)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    return { success: false, errors: ["No positions data provided"], status: :unprocessable_entity } if positions_data.blank?
    
    # Group positions by option_group_id to handle each group separately
    options_by_group = {}
    
    # First, collect all options and organize them by group
    positions_data.each do |position_item|
      option = find_option_with_tenant_scope(position_item[:id])
      next unless option
      
      group_id = option.option_group_id
      options_by_group[group_id] ||= []
      options_by_group[group_id] << { option: option, position: position_item[:position].to_i }
    end
    
    return { success: false, errors: ["No valid options found"], status: :not_found } if options_by_group.empty?
    
    # Now update positions for each group
    updated_count = 0
    
    ActiveRecord::Base.transaction do
      options_by_group.each do |group_id, options|
        # Sort by the new position
        sorted_options = options.sort_by { |item| item[:position] }
        
        # Assign normalized positions (1, 2, 3...) to ensure no gaps
        sorted_options.each_with_index do |item, index|
          normalized_position = index + 1
          if item[:option].update(position: normalized_position)
            updated_count += 1
          end
        end
      end
    end
    
    if updated_count > 0
      { success: true, updated_count: updated_count }
    else
      { success: false, errors: ["Failed to update option positions"], status: :unprocessable_entity }
    end
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
    return option_group if menu.restaurant_id == @restaurant.id
    
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
    return option if menu.restaurant_id == @restaurant.id
    
    nil
  end
end
