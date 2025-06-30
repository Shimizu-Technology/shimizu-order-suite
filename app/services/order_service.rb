# app/services/order_service.rb
#
# The OrderService class provides methods for working with orders
# in a tenant-isolated way. It ensures that all order operations
# are properly scoped to the current restaurant.
#
class OrderService < TenantScopedService
  # Find all orders for the current restaurant with optional filtering
  # @param filters [Hash] Additional filters to apply to the query
  # @return [ActiveRecord::Relation] A relation of orders for the current restaurant
  def find_orders(filters = {})
    find_records(Order, filters)
  end
  
  # Find recent orders for the current restaurant
  # @param limit [Integer] Maximum number of orders to return
  # @return [ActiveRecord::Relation] A relation of recent orders
  def find_recent_orders(limit = 10)
    scope_query(Order)
      .includes(:user, :menu_items)
      .order(created_at: :desc)
      .limit(limit)
  end
  
  # Find an order by ID, ensuring it belongs to the current restaurant
  # @param id [Integer] The ID of the order to find
  # @return [Order, nil] The found order or nil
  def find_order_by_id(id)
    find_record_by_id(Order, id)
  end
  
  # Create a new order for the current restaurant
  # @param attributes [Hash] Attributes for the new order
  # @return [Order] The created order
  def create_order(attributes = {})
    # If location_id is not provided, use the default location
    if attributes[:location_id].blank?
      default_location = find_default_location
      attributes[:location_id] = default_location&.id
    end
    
    create_record(Order, attributes)
  end
  
  # Find orders for a specific location
  # @param location_id [Integer] The ID of the location to find orders for
  # @param filters [Hash] Additional filters to apply to the query
  # @return [ActiveRecord::Relation] A relation of orders for the specified location
  def find_orders_by_location(location_id, filters = {})
    find_records(Order, filters.merge(location_id: location_id))
  end
  
  # Find the default location for the current restaurant
  # @return [Location, nil] The default location or nil if none exists
  def find_default_location
    find_records(Location).find_by(is_default: true)
  end
  
  # Update an order, ensuring it belongs to the current restaurant
  # @param order [Order] The order to update
  # @param attributes [Hash] New attributes for the order
  # @return [Boolean] Whether the update was successful
  def update_order(order, attributes = {})
    update_record(order, attributes)
  end
  
  # Cancel an order, ensuring it belongs to the current restaurant
  # @param order [Order] The order to cancel
  # @param reason [String] The reason for cancellation
  # @return [Boolean] Whether the cancellation was successful
  def cancel_order(order, reason = nil)
    ensure_record_belongs_to_restaurant(order)
    
    order.update(
      status: "cancelled",
      cancellation_reason: reason,
      cancelled_at: Time.current
    )
  end
  
  # Get order statistics for the current restaurant
  # @param start_date [Date] Start date for the statistics
  # @param end_date [Date] End date for the statistics
  # @return [Hash] Order statistics
  def get_order_statistics(start_date = 30.days.ago, end_date = Time.current)
    # Ensure we're working with the right time objects
    start_time = start_date.beginning_of_day
    end_time = end_date.end_of_day
    
    # Get orders in the date range
    orders = scope_query(Order)
      .where(created_at: start_time..end_time)
      .where.not(status: "cancelled")
    
    # Calculate statistics
    total_count = orders.count
    total_revenue = orders.sum(:total_amount)
    average_order_value = total_count > 0 ? total_revenue / total_count : 0
    
    {
      total_count: total_count,
      total_revenue: total_revenue,
      average_order_value: average_order_value,
      start_date: start_time,
      end_date: end_time,
      restaurant_id: @restaurant.id,
      restaurant_name: @restaurant.name
    }
  end

  # ========================================
  # Option-Level Inventory Processing
  # ========================================

  # Process inventory for order items, handling both item-level and option-level tracking
  # @param order_items [Array] Array of order items with menu_id and customizations
  # @param order [Order] The order being processed
  # @param user [User] The user placing/updating the order
  # @param operation [String] The type of operation ('order', 'cancel', 'update')
  # @return [Hash] Result with success status and any errors
  def process_order_inventory(order_items, order, user, operation = 'order')
    ensure_record_belongs_to_restaurant(order)
    
    result = { success: true, errors: [], inventory_changes: [] }
    
    begin
      ActiveRecord::Base.transaction do
        order_items.each do |item|
          item_result = process_single_item_inventory(item, order, user, operation)
          
          unless item_result[:success]
            result[:success] = false
            result[:errors].concat(item_result[:errors])
          end
          
          result[:inventory_changes].concat(item_result[:inventory_changes]) if item_result[:inventory_changes]
        end
        
        # Rollback transaction if there were any errors
        raise ActiveRecord::Rollback unless result[:success]
      end
      
      Rails.logger.info("OrderService: Successfully processed inventory for order #{order.id}")
      
    rescue StandardError => e
      Rails.logger.error("OrderService: Error processing inventory for order #{order.id}: #{e.message}")
      result[:success] = false
      result[:errors] << "Failed to process inventory: #{e.message}"
    end
    
    result
  end

  # Revert inventory changes for an order (used for cancellations/refunds)
  # @param order_items [Array] Array of order items to revert
  # @param order [Order] The order being reverted
  # @param user [User] The user performing the reversion
  # @return [Hash] Result with success status and any errors
  def revert_order_inventory(order_items, order, user)
    ensure_record_belongs_to_restaurant(order)
    
    result = { success: true, errors: [], inventory_changes: [] }
    
    begin
      ActiveRecord::Base.transaction do
        order_items.each do |item|
          item_result = process_single_item_inventory(item, order, user, 'revert')
          
          unless item_result[:success]
            result[:success] = false
            result[:errors].concat(item_result[:errors])
          end
          
          result[:inventory_changes].concat(item_result[:inventory_changes]) if item_result[:inventory_changes]
        end
        
        # Rollback transaction if there were any errors
        raise ActiveRecord::Rollback unless result[:success]
      end
      
      Rails.logger.info("OrderService: Successfully reverted inventory for order #{order.id}")
      
    rescue StandardError => e
      Rails.logger.error("OrderService: Error reverting inventory for order #{order.id}: #{e.message}")
      result[:success] = false
      result[:errors] << "Failed to revert inventory: #{e.message}"
    end
    
    result
  end
  
  private

  # Process inventory for a single order item
  # @param item [Hash] Order item with menu_id, quantity, and customizations
  # @param order [Order] The order being processed
  # @param user [User] The user placing/updating the order
  # @param operation [String] The type of operation ('order', 'revert', 'update')
  # @return [Hash] Result with success status and any errors
  def process_single_item_inventory(item, order, user, operation)
    menu_item_id = extract_menu_item_id(item)
    quantity = extract_item_quantity(item)
    customizations = extract_customizations(item)
    damage_action = extract_damage_action(item)
    
    return { success: true, errors: [], inventory_changes: [] } unless menu_item_id.present?
    
    menu_item = MenuItem.find_by(id: menu_item_id)
    return { success: true, errors: [], inventory_changes: [] } unless menu_item&.enable_stock_tracking
    
    result = { success: true, errors: [], inventory_changes: [] }
    
    # Handle damaged items during refunds - mark as damaged instead of restoring inventory
    if operation == 'revert' && damage_action&.dig('mark_as_damaged')
      damage_result = process_damaged_item(menu_item, damage_action, quantity, order, user, customizations)
      result.merge!(damage_result)
      return result
    end
    
    # Check if this menu item uses option-level inventory tracking
    if menu_item.uses_option_level_inventory?
      # Process option-level inventory
      option_result = process_option_inventory(menu_item, customizations, quantity, order, user, operation)
      result.merge!(option_result)
    else
      # Process traditional item-level inventory
      item_result = process_item_level_inventory(menu_item, quantity, order, user, operation)
      result.merge!(item_result)
    end
    
    result
  end

  # Process option-level inventory using OptionInventoryService
  # @param menu_item [MenuItem] The menu item being processed
  # @param customizations [Hash] Order customizations containing option selections
  # @param quantity [Integer] Quantity being ordered
  # @param order [Order] The order being processed
  # @param user [User] The user placing/updating the order
  # @param operation [String] The type of operation ('order', 'revert')
  # @return [Hash] Result with success status and any errors
  def process_option_inventory(menu_item, customizations, quantity, order, user, operation)
    # Build order item structure for OptionInventoryService
    order_item = {
      'menu_item_id' => menu_item.id,
      'quantity' => quantity,
      'customizations' => transform_customizations_for_options(customizations, menu_item)
    }
    
    result = case operation
    when 'order'
      OptionInventoryService.process_order_inventory([order_item], user, order)
    when 'revert'
      OptionInventoryService.revert_order_inventory([order_item], user, order)
    else
      { success: false, errors: ["Unknown operation: #{operation}"], inventory_changes: [] }
    end
    
    # Convert OptionInventoryService response format to consistent inventory_changes format
    if result[:success] && (result[:processed_items] || result[:reverted_items])
      items = result[:processed_items] || result[:reverted_items] || []
      inventory_changes = items.map do |item|
        if item[:option_id]
          {
            type: 'option_level',
            option_id: item[:option_id],
            quantity_change: operation == 'revert' ? item[:quantity_restored] : -item[:quantity_reduced],
            operation: operation
          }
        elsif item[:menu_item_id]
          {
            type: 'item_level_sync',
            menu_item_id: item[:menu_item_id],
            previous_stock: item[:previous_stock],
            new_stock: item[:new_stock],
            quantity_change: item[:quantity_restored] || item[:quantity_reduced] || 0
          }
        end
      end.compact
      
      {
        success: result[:success],
        errors: result[:errors] || [],
        inventory_changes: inventory_changes
      }
    else
      {
        success: result[:success] || false,
        errors: result[:errors] || [],
        inventory_changes: []
      }
    end
  end

  # Process traditional item-level inventory
  # @param menu_item [MenuItem] The menu item being processed
  # @param quantity [Integer] Quantity being ordered
  # @param order [Order] The order being processed
  # @param user [User] The user placing/updating the order
  # @param operation [String] The type of operation ('order', 'revert')
  # @return [Hash] Result with success status and any errors
  def process_item_level_inventory(menu_item, quantity, order, user, operation)
    result = { success: true, errors: [], inventory_changes: [] }
    
    begin
      case operation
      when 'order'
        # Reduce stock for new order
        current_stock = menu_item.stock_quantity.to_i
        new_stock = [current_stock - quantity, 0].max
        
        menu_item.update_stock_quantity(
          new_stock,
          "order",
          "Order ##{order.order_number.presence || order.id} - #{quantity} items",
          user,
          order
        )
        
        result[:inventory_changes] << {
          type: 'item_level',
          menu_item_id: menu_item.id,
          menu_item_name: menu_item.name,
          previous_stock: current_stock,
          new_stock: new_stock,
          quantity_change: -quantity
        }
        
      when 'revert'
        # Restore stock for cancelled/refunded order
        current_stock = menu_item.stock_quantity.to_i
        new_stock = current_stock + quantity
        
        menu_item.update_stock_quantity(
          new_stock,
          "adjustment",
          "Inventory Adjustment: Order ##{order.order_number.presence || order.id} - Reverted #{quantity} items (restored to inventory)",
          user,
          order
        )
        
        result[:inventory_changes] << {
          type: 'item_level',
          menu_item_id: menu_item.id,
          menu_item_name: menu_item.name,
          previous_stock: current_stock,
          new_stock: new_stock,
          quantity_change: quantity
        }
      end
      
    rescue StandardError => e
      Rails.logger.error("OrderService: Error processing item-level inventory for #{menu_item.name}: #{e.message}")
      result[:success] = false
      result[:errors] << "Failed to process inventory for #{menu_item.name}: #{e.message}"
    end
    
    result
  end

  # Extract menu item ID from order item hash or ActionController::Parameters
  # @param item [Hash|ActionController::Parameters] Order item
  # @return [Integer, nil] Menu item ID
  def extract_menu_item_id(item)
    if item.respond_to?(:[])
      item[:id] || item["id"] || item[:menu_id] || item["menu_id"] || item[:menu_item_id] || item["menu_item_id"]
    elsif item.respond_to?(:id)
      item.id
    elsif item.respond_to?(:menu_id)
      item.menu_id
    end
  end

  # Extract quantity from order item hash or ActionController::Parameters
  # @param item [Hash|ActionController::Parameters] Order item
  # @return [Integer] Quantity (defaults to 1)
  def extract_item_quantity(item)
    quantity = 1 # Default
    if item.respond_to?(:[])
      quantity = (item[:quantity] || item["quantity"] || 1).to_i
    elsif item.respond_to?(:quantity)
      quantity = item.quantity.to_i
    end
    [quantity, 1].max # Ensure at least 1
  end

  # Extract customizations from order item hash or ActionController::Parameters
  # @param item [Hash|ActionController::Parameters] Order item
  # @return [Hash] Customizations hash
  def extract_customizations(item)
    if item.respond_to?(:[])
      customizations = item[:customizations] || item["customizations"] || {}
      # Convert ActionController::Parameters to regular hash if needed
      customizations.respond_to?(:to_unsafe_h) ? customizations.to_unsafe_h : customizations
    else
      {}
    end
  end

  # Extract damage action from order item hash or ActionController::Parameters
  # @param item [Hash|ActionController::Parameters] Order item
  # @return [Hash] Damage action hash
  def extract_damage_action(item)
    if item.respond_to?(:[])
      damage_action = item[:damage_action] || item["damage_action"] || {}
      # Convert ActionController::Parameters to regular hash if needed
      damage_action.respond_to?(:to_unsafe_h) ? damage_action.to_unsafe_h : damage_action
    else
      {}
    end
  end

  # Transform customizations hash to include option_id for OptionInventoryService
  # @param customizations [Hash] Original customizations from order
  # @param menu_item [MenuItem] The menu item to process options for
  # @return [Array] Array of customizations with option_id
  def transform_customizations_for_options(customizations, menu_item)
    return [] unless customizations.present? && menu_item.uses_option_level_inventory?
    
    tracking_group = menu_item.option_inventory_tracking_group
    return [] unless tracking_group
    
    option_customizations = []
    
    Rails.logger.debug("Transform customizations for #{menu_item.name}: #{customizations.inspect}")
    Rails.logger.debug("Tracking group: #{tracking_group.name} (ID: #{tracking_group.id})")
    
    # Find customizations that match options in the tracking group
    customizations.each do |key, value|
      Rails.logger.debug("Checking customization key: '#{key}' (#{key.class}) with value: #{value.inspect}")
      
      # Look for option group customizations
      if key.to_s == tracking_group.id.to_s || key.to_s == tracking_group.name
        Rails.logger.debug("Key matches tracking group!")
        # Handle both single values and arrays of values
        values_array = Array(value).flatten
        Rails.logger.debug("Values array: #{values_array.inspect}")
        
        values_array.each do |single_value|
          Rails.logger.debug("Looking for option with ID or name: '#{single_value}'")
          option = tracking_group.options.find_by(id: single_value) || tracking_group.options.find_by(name: single_value)
          if option
            Rails.logger.debug("Found option: #{option.name} (ID: #{option.id})")
            option_customizations << { 'option_id' => option.id }
          else
            Rails.logger.warn("No option found for value: '#{single_value}'")
          end
        end
      else
        Rails.logger.debug("Key '#{key}' does not match tracking group '#{tracking_group.name}' or ID '#{tracking_group.id}'")
      end
    end
    
    Rails.logger.debug("Final option customizations: #{option_customizations.inspect}")
    option_customizations
  end

  # Process damaged items by marking them as damaged instead of restoring inventory
  # @param menu_item [MenuItem] The menu item being processed
  # @param damage_action [Hash] Damage action information
  # @param quantity [Integer] Quantity being processed
  # @param order [Order] The order being processed
  # @param user [User] The user processing the damage
  # @param customizations [Hash] Order customizations for option-level items
  # @return [Hash] Result with success status and any errors
  def process_damaged_item(menu_item, damage_action, quantity, order, user, customizations)
    damage_reason = damage_action['damage_reason'] || 'Damaged during order cancellation'
    damage_quantity = (damage_action['damage_quantity'] || quantity).to_i
    
    Rails.logger.info("Processing damaged item: #{menu_item.name} (ID: #{menu_item.id}) - Quantity: #{damage_quantity}, Reason: #{damage_reason}")
    
    result = { success: true, errors: [], inventory_changes: [] }
    
    begin
      if menu_item.uses_option_level_inventory?
        # Handle option-level damaged items
        damage_result = process_option_damaged_item(menu_item, customizations, damage_quantity, damage_reason, order, user)
        result.merge!(damage_result)
      else
        # Handle menu item-level damaged items
        # Use increment_damaged_only since this is during a refund (inventory already adjusted)
        if menu_item.increment_damaged_only(damage_quantity, damage_reason, user)
          result[:inventory_changes] << {
            type: 'item_level_damaged',
            menu_item_id: menu_item.id,
            menu_item_name: menu_item.name,
            quantity_damaged: damage_quantity,
            damage_reason: damage_reason
          }
          Rails.logger.info("Marked #{damage_quantity} of menu item #{menu_item.id} as damaged: #{damage_reason}")
        else
          result[:success] = false
          result[:errors] << "Failed to mark items as damaged for #{menu_item.name}"
        end
      end
    rescue StandardError => e
      Rails.logger.error("Error processing damaged item #{menu_item.name}: #{e.message}")
      result[:success] = false
      result[:errors] << "Failed to process damaged item #{menu_item.name}: #{e.message}"
    end
    
    result
  end

  # Process option-level damaged items
  # @param menu_item [MenuItem] The menu item with option inventory
  # @param customizations [Hash] Order customizations containing option selections
  # @param damage_quantity [Integer] Quantity to mark as damaged
  # @param damage_reason [String] Reason for damage
  # @param order [Order] The order being processed
  # @param user [User] The user processing the damage
  # @return [Hash] Result with success status and any errors
  def process_option_damaged_item(menu_item, customizations, damage_quantity, damage_reason, order, user)
    result = { success: true, errors: [], inventory_changes: [] }
    
    # Transform customizations to option_id format
    option_customizations = transform_customizations_for_options(customizations, menu_item)
    
    if option_customizations.empty?
      Rails.logger.warn("No valid option customizations found for damaged item #{menu_item.name}")
      result[:success] = false
      result[:errors] << "No valid options found for damaged item #{menu_item.name}"
      return result
    end
    
    # Process damage for each selected option with synchronized updates
    ActiveRecord::Base.transaction do
      # Track totals for menu item synchronization
      total_stock_adjustment = 0
      total_damage_adjustment = 0
      
      option_customizations.each do |option_custom|
        option_id = option_custom['option_id']
        option = Option.find_by(id: option_id)
        
        if option
          # Capture previous quantities for audit
          previous_stock = option.stock_quantity || 0
          previous_damaged = option.damaged_quantity || 0
          
          # Calculate new quantities
          new_stock = previous_stock + damage_quantity
          new_damaged = previous_damaged + damage_quantity
          
          # Update option using update_columns to bypass validations during synchronized update
          option.update_columns(
            stock_quantity: new_stock,
            damaged_quantity: new_damaged,
            updated_at: Time.current
          )
          
          # Create audit records
          OptionStockAudit.create_damaged_record(option, damage_quantity, damage_reason, user)
          OptionStockAudit.create_stock_record(
            option,
            new_stock,
            "adjustment",
            "Stock adjusted to match damaged items from order",
            user,
            order
          )
          
          # Track adjustments for menu item synchronization
          total_stock_adjustment += damage_quantity
          total_damage_adjustment += damage_quantity
          
          result[:inventory_changes] << {
            type: 'option_level_damaged',
            option_id: option.id,
            option_name: option.name,
            quantity_damaged: damage_quantity,
            damage_reason: damage_reason
          }
          
          Rails.logger.info("Marked #{damage_quantity} of option #{option_id} (#{option.name}) as damaged: #{damage_reason}")
        else
          Rails.logger.warn("Option not found for ID: #{option_id}")
          result[:success] = false
          result[:errors] << "Option not found for ID: #{option_id}"
        end
      end
      
      # Synchronize menu item inventory if we successfully processed options
      if result[:success] && total_stock_adjustment > 0
        # Update menu item stock and damage quantities to stay in sync with options
        menu_item_previous_stock = menu_item.stock_quantity || 0
        menu_item_previous_damaged = menu_item.damaged_quantity || 0
        
        new_menu_item_stock = menu_item_previous_stock + total_stock_adjustment
        new_menu_item_damaged = menu_item_previous_damaged + total_damage_adjustment
        
        # Use update_columns to bypass validations during synchronized update
        menu_item.update_columns(
          stock_quantity: new_menu_item_stock,
          damaged_quantity: new_menu_item_damaged,
          updated_at: Time.current
        )
        
        # Create menu item audit records
        MenuItemStockAudit.create_damaged_record(menu_item, total_damage_adjustment, damage_reason, user)
        MenuItemStockAudit.create_stock_record(
          menu_item,
          new_menu_item_stock,
          "adjustment",
          "Stock adjusted to match damaged option items from order",
          user,
          order
        )
        
        result[:inventory_changes] << {
          type: 'item_level_sync_damaged',
          menu_item_id: menu_item.id,
          menu_item_name: menu_item.name,
          quantity_damaged: total_damage_adjustment,
          quantity_stock_adjusted: total_stock_adjustment,
          damage_reason: damage_reason
        }
        
        Rails.logger.info("Synchronized menu item #{menu_item.id} with option damage: +#{total_stock_adjustment} stock, +#{total_damage_adjustment} damaged")
      end
    end
    
    result
  end
  
  # Additional private methods specific to order operations can be added here
end
