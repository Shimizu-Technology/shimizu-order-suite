# app/services/option_inventory_service.rb

class OptionInventoryService
  # Enable option inventory tracking for an option group
  def self.enable_option_tracking(option_group, current_user = nil)
    begin
      return { success: false, errors: ["Option group not found"], status: :not_found } unless option_group

      # Validate that the menu item has stock tracking enabled
      unless option_group.menu_item&.enable_stock_tracking
        return { 
          success: false, 
          errors: ["Menu item must have stock tracking enabled first"], 
          status: :unprocessable_entity 
        }
      end

      # Check if another option group already has tracking enabled
      existing_tracking_group = option_group.menu_item.option_groups.where(enable_inventory_tracking: true).first
      if existing_tracking_group && existing_tracking_group.id != option_group.id
        return { 
          success: false, 
          errors: ["Only one option group per menu item can have inventory tracking enabled"], 
          status: :unprocessable_entity 
        }
      end

      ActiveRecord::Base.transaction do
        # Enable tracking on the option group (bypass validations for initial enable)
        option_group.update_column(:enable_inventory_tracking, true)

        # Initialize option stock quantities to match proportions if menu item has stock
        if option_group.menu_item.stock_quantity&.positive?
          initialize_option_stock_quantities(option_group)
          
          # Create audit records for the fresh start
          option_group.options.each do |option|
            OptionStockAudit.create_stock_record(
              option,
              option.stock_quantity,
              "tracking_enabled",
              "Inventory tracking enabled - fresh start with stock distributed from menu item (#{option_group.menu_item.stock_quantity} total)",
              current_user
            )
          end
        else
          # Reset all option inventory fields to 0 when no menu item stock
          option_group.options.update_all(stock_quantity: 0, damaged_quantity: 0)
          
          # Create audit records for the fresh start
          option_group.options.each do |option|
            OptionStockAudit.create_stock_record(
              option.reload,
              0,
              "tracking_enabled",
              "Inventory tracking enabled - fresh start with no initial stock",
              current_user
            )
          end
        end

        # Validate after initialization to ensure everything is correct
        option_group.reload
        unless option_group.valid?
          raise ActiveRecord::RecordInvalid.new(option_group)
        end

        Rails.logger.info("Option inventory tracking enabled for option group #{option_group.id} by user #{current_user&.id}")
      end

      { success: true, option_group: option_group, status: :ok }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors.full_messages, status: :unprocessable_entity }
    rescue => e
      Rails.logger.error("Failed to enable option tracking: #{e.message}")
      { success: false, errors: ["Failed to enable option inventory tracking"], status: :internal_server_error }
    end
  end

  # Disable option inventory tracking for an option group
  def self.disable_option_tracking(option_group, current_user = nil)
    begin
      return { success: false, errors: ["Option group not found"], status: :not_found } unless option_group

      ActiveRecord::Base.transaction do
        # Create audit records before resetting (to capture the final state)
        option_group.options.each do |option|
          OptionStockAudit.create_stock_record(
            option,
            0,
            "tracking_disabled",
            "Inventory tracking disabled - all quantities reset to 0",
            current_user
          )
        end
        
        # Reset all option stock quantities to 0
        option_group.options.update_all(stock_quantity: 0, damaged_quantity: 0)

        # Disable tracking on the option group
        option_group.update!(enable_inventory_tracking: false)

        Rails.logger.info("Option inventory tracking disabled for option group #{option_group.id} by user #{current_user&.id}")
      end

      { success: true, option_group: option_group, status: :ok }
    rescue => e
      Rails.logger.error("Failed to disable option tracking: #{e.message}")
      { success: false, errors: ["Failed to disable option inventory tracking"], status: :internal_server_error }
    end
  end

  # Update stock quantities for multiple options
  def self.update_option_quantities(option_group, quantities_hash, current_user = nil, reason = nil)
    begin
      return { success: false, errors: ["Option group not found"], status: :not_found } unless option_group
      return { success: false, errors: ["Option inventory tracking not enabled"], status: :unprocessable_entity } unless option_group.inventory_tracking_enabled?

      # For option-level tracking, auto-sync menu item stock to match option total
      total_option_stock = quantities_hash.values.sum(&:to_i)
      menu_item = option_group.menu_item
      current_menu_item_stock = menu_item.stock_quantity&.to_i || 0

      # Auto-sync menu item stock to match option quantities total for option-level tracking
      if total_option_stock != current_menu_item_stock
        Rails.logger.info("Auto-syncing menu item #{menu_item.id} stock from #{current_menu_item_stock} to #{total_option_stock} to match option quantities")
        adjustment_reason = reason || "Auto-sync: Updated menu item stock to match option quantities total (#{total_option_stock})"
        menu_item.update_stock_quantity(
          total_option_stock,
          "option_sync", 
          adjustment_reason,
          current_user
        )
      end

      updated_options = []
      
      ActiveRecord::Base.transaction do
        # Update all options at once to avoid individual validation conflicts
        quantities_hash.each do |option_id, quantity|
          option = option_group.options.find_by(id: option_id)
          next unless option

          old_quantity = option.stock_quantity
          
          # Use update_column to bypass validations for bulk updates
          option.update_column(:stock_quantity, quantity.to_i)
          updated_options << option

          # Create audit record with proper reason
          audit_reason = reason || "Manual stock update (#{option.name})"
          OptionStockAudit.create_stock_record(option, quantity.to_i, :adjustment, audit_reason, current_user)

          Rails.logger.info("Updated option #{option_id} stock from #{old_quantity} to #{quantity} by user #{current_user&.id} - Reason: #{audit_reason}")
        end

        # Reload options to get fresh data
        updated_options.each(&:reload)
        
        # Now validate synchronization as a final check
        unless validate_inventory_synchronization(menu_item)
          raise "Inventory synchronization validation failed after bulk update"
        end
      end

      { success: true, updated_options: updated_options, status: :ok }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors.full_messages, status: :unprocessable_entity }
    rescue => e
      Rails.logger.error("Failed to update option quantities: #{e.message}")
      { success: false, errors: ["Failed to update option quantities"], status: :internal_server_error }
    end
  end

  # Update a single option quantity without affecting other options
  def self.update_single_option_quantity(option_group, option_id, quantity, current_user = nil, reason = nil)
    begin
      return { success: false, errors: ["Option group not found"], status: :not_found } unless option_group
      return { success: false, errors: ["Option inventory tracking not enabled"], status: :unprocessable_entity } unless option_group.inventory_tracking_enabled?

      option = option_group.options.find_by(id: option_id)
      return { success: false, errors: ["Option not found"], status: :not_found } unless option

      old_quantity = option.stock_quantity
      new_quantity = quantity.to_i

      # Validate the new quantity
      if new_quantity < 0
        return { success: false, errors: ["Quantity cannot be negative"], status: :unprocessable_entity }
      end

      ActiveRecord::Base.transaction do
        # Calculate the difference in stock for this option
        quantity_difference = new_quantity - old_quantity
        
        # Update the specific option
        option.update_column(:stock_quantity, new_quantity)

        # Adjust menu item stock by the same difference (no redistribution)
        menu_item = option_group.menu_item
        current_menu_item_stock = menu_item.stock_quantity&.to_i || 0
        new_menu_item_stock = current_menu_item_stock + quantity_difference

        # Ensure menu item stock doesn't go negative
        if new_menu_item_stock < 0
          raise "Menu item stock would become negative (#{new_menu_item_stock}). Cannot reduce option below available menu item stock."
        end

        # Update menu item stock with proper reason
        menu_item_reason = reason || "Single option update: #{option.name} changed from #{old_quantity} to #{new_quantity}"
        menu_item.update_stock_quantity(
          new_menu_item_stock,
          "option_update", 
          menu_item_reason,
          current_user
        )

        # Create audit record for the option with proper reason
        audit_reason = reason || "Single option inventory adjustment (#{option.name})"
        OptionStockAudit.create_stock_record(option, new_quantity, :adjustment, audit_reason, current_user)

        Rails.logger.info("Updated single option #{option_id} stock from #{old_quantity} to #{new_quantity}, adjusted menu item stock by #{quantity_difference} to #{new_menu_item_stock} - Reason: #{audit_reason}")
      end

      { success: true, option: option.reload, status: :ok }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors.full_messages, status: :unprocessable_entity }
    rescue => e
      Rails.logger.error("Failed to update single option quantity: #{e.message}")
      { success: false, errors: [e.message], status: :internal_server_error }
    end
  end

  # Process inventory for an order (reduce stock)
  def self.process_order_inventory(order_items, current_user = nil, order = nil)
    begin
      processed_items = []
      menu_items_to_sync = Set.new

      ActiveRecord::Base.transaction do
        order_items.each do |order_item|
          next unless order_item['customizations']&.any?

          menu_item = MenuItem.find_by(id: order_item['menu_item_id'])
          next unless menu_item&.uses_option_level_inventory?

          tracking_group = menu_item.option_inventory_tracking_group
          next unless tracking_group

          order_quantity = order_item['quantity'].to_i

          # Process each customization
          order_item['customizations'].each do |customization|
            option = tracking_group.options.find_by(id: customization['option_id'])
            next unless option

            quantity_to_reduce = order_quantity
            
            if option.available_stock >= quantity_to_reduce
              # Capture previous stock before reducing
              previous_stock = option.stock_quantity
              
              # Reduce option stock (bypass validations for synchronized updates)
              option.update_column(:stock_quantity, option.stock_quantity - quantity_to_reduce)
              processed_items << { option_id: option.id, quantity_reduced: quantity_to_reduce }
              
              # Create audit record for sale with correct previous quantity
              order_info = order ? "##{order.order_number.presence || order.id}" : ""
              OptionStockAudit.create!(
                option: option,
                previous_quantity: previous_stock,
                new_quantity: option.stock_quantity,
                reason: "Sale: Order #{order_info} - #{option.name}",
                user: current_user,
                order: order
              )
              
              Rails.logger.info("Reduced option #{option.id} stock by #{quantity_to_reduce} for order")
            else
              raise "Insufficient stock for option #{option.name}. Available: #{option.available_stock}, Required: #{quantity_to_reduce}"
            end
          end

          # Also reduce menu item stock to keep both levels in sync
          if menu_item.stock_quantity && menu_item.stock_quantity >= order_quantity
            previous_stock = menu_item.stock_quantity
            new_stock = [previous_stock - order_quantity, 0].max
            
            # Build description of options selected for this order item
            selected_options = []
            order_item['customizations'].each do |customization|
              selected_option = tracking_group.options.find_by(id: customization['option_id'])
              selected_options << selected_option.name if selected_option
            end
            options_description = selected_options.any? ? " (#{selected_options.join(', ')})" : ""
            order_info = order ? "##{order.order_number.presence || order.id}" : ""
            
            menu_item.update_stock_quantity(
              new_stock,
              "order",
              "Order #{order_info} - #{order_quantity} items#{options_description}",
              current_user,
              order
            )
            
            processed_items << { 
              menu_item_id: menu_item.id, 
              quantity_reduced: order_quantity,
              previous_stock: previous_stock,
              new_stock: new_stock
            }
            
                      Rails.logger.info("Reduced menu item #{menu_item.id} stock by #{order_quantity} for order (option-level tracking)")
        else
          Rails.logger.warn("Menu item #{menu_item.id} has insufficient stock (#{menu_item.stock_quantity}) for order quantity #{order_quantity}")
        end

        # Validate synchronization after processing
        unless validate_inventory_synchronization(menu_item)
          Rails.logger.error("Inventory synchronization lost after processing order for menu item #{menu_item.id}")
          raise "Inventory synchronization error: option totals no longer match menu item stock"
        end
        end
      end

      { success: true, processed_items: processed_items, status: :ok }
    rescue => e
      Rails.logger.error("Failed to process order inventory: #{e.message}")
      { success: false, errors: [e.message], status: :unprocessable_entity }
    end
  end

  # Revert inventory for an order (increase stock back)
  def self.revert_order_inventory(order_items, current_user = nil, order = nil)
    begin
      reverted_items = []

      ActiveRecord::Base.transaction do
        order_items.each do |order_item|
          next unless order_item['customizations']&.any?

          menu_item = MenuItem.find_by(id: order_item['menu_item_id'])
          next unless menu_item&.uses_option_level_inventory?

          tracking_group = menu_item.option_inventory_tracking_group
          next unless tracking_group

          order_quantity = order_item['quantity'].to_i

          # Revert each customization
          order_item['customizations'].each do |customization|
            option = tracking_group.options.find_by(id: customization['option_id'])
            next unless option

            quantity_to_restore = order_quantity
            
            # Capture previous stock before increasing
            previous_stock = option.stock_quantity
            
            # Increase option stock (bypass validations for synchronized updates)
            option.update_column(:stock_quantity, option.stock_quantity + quantity_to_restore)
            reverted_items << { option_id: option.id, quantity_restored: quantity_to_restore }
            
            # Create audit record for refund/cancellation with correct previous quantity
            order_info = order ? "##{order.order_number.presence || order.id}" : ""
            OptionStockAudit.create!(
              option: option,
              previous_quantity: previous_stock,
              new_quantity: option.stock_quantity,
              reason: "Restock: Order #{order_info} cancellation/refund - #{option.name}",
              user: current_user,
              order: order
            )
            
            Rails.logger.info("Restored option #{option.id} stock by #{quantity_to_restore} for order cancellation/refund")
          end

          # Also restore menu item stock to keep both levels in sync
          if menu_item.stock_quantity
            previous_stock = menu_item.stock_quantity
            new_stock = previous_stock + order_quantity
            
            # Build description of options selected for this order item
            selected_options = []
            order_item['customizations'].each do |customization|
              selected_option = tracking_group.options.find_by(id: customization['option_id'])
              selected_options << selected_option.name if selected_option
            end
            options_description = selected_options.any? ? " (#{selected_options.join(', ')})" : ""
            order_info = order ? "##{order.order_number.presence || order.id}" : ""
            
            menu_item.update_stock_quantity(
              new_stock,
              "adjustment",
              "Order #{order_info} cancellation/refund - #{order_quantity} items#{options_description}",
              current_user,
              order
            )
            
            reverted_items << { 
              menu_item_id: menu_item.id, 
              quantity_restored: order_quantity,
              previous_stock: previous_stock,
              new_stock: new_stock
            }
            
            Rails.logger.info("Restored menu item #{menu_item.id} stock by #{order_quantity} for order cancellation/refund (option-level tracking)")
          end

          # Validate synchronization after reverting
          unless validate_inventory_synchronization(menu_item)
            Rails.logger.error("Inventory synchronization lost after reverting order for menu item #{menu_item.id}")
            raise "Inventory synchronization error: option totals no longer match menu item stock"
          end
        end
      end

      { success: true, reverted_items: reverted_items, status: :ok }
    rescue => e
      Rails.logger.error("Failed to revert order inventory: #{e.message}")
      { success: false, errors: [e.message], status: :internal_server_error }
    end
  end

  # Mark options as damaged
  def self.mark_options_damaged(option_group, damage_hash, reason, current_user = nil)
    begin
      return { success: false, errors: ["Option group not found"], status: :not_found } unless option_group
      return { success: false, errors: ["Option inventory tracking not enabled"], status: :unprocessable_entity } unless option_group.inventory_tracking_enabled?

      damaged_options = []

      ActiveRecord::Base.transaction do
        damage_hash.each do |option_id, quantity|
          option = option_group.options.find_by(id: option_id)
          next unless option

          if option.mark_damaged!(quantity.to_i)
            damaged_options << { option_id: option.id, quantity_damaged: quantity.to_i }
            
            # Create audit record for damaged items
            OptionStockAudit.create_damaged_record(option, quantity.to_i, reason, current_user)
            
            Rails.logger.info("Marked #{quantity} of option #{option_id} as damaged: #{reason} by user #{current_user&.id}")
          else
            raise "Cannot mark #{quantity} of option #{option.name} as damaged. Available stock: #{option.available_stock}"
          end
        end
      end

      { success: true, damaged_options: damaged_options, status: :ok }
    rescue => e
      Rails.logger.error("Failed to mark options as damaged: #{e.message}")
      { success: false, errors: [e.message], status: :unprocessable_entity }
    end
  end

  private

  # Initialize option stock quantities proportionally based on menu item stock
  def self.initialize_option_stock_quantities(option_group)
    menu_item_stock = option_group.menu_item.stock_quantity.to_i
    options_count = option_group.options.count
    
    return if options_count.zero?

    per_option = menu_item_stock / options_count
    remainder = menu_item_stock % options_count

    option_group.options.each_with_index do |option, index|
      additional = index < remainder ? 1 : 0
      new_quantity = per_option + additional
      
      # Reset ALL inventory-related fields for fresh start
      option.update_columns(
        stock_quantity: new_quantity,
        damaged_quantity: 0  # Always start fresh with no damaged items
      )
      
      Rails.logger.info("Initialized option #{option.id} (#{option.name}) - Stock: #{new_quantity}, Damaged: 0 (fresh start)")
    end
  end

  # Sync menu item inventory to match option totals
  def self.sync_menu_item_inventory(option_group)
    total_option_stock = option_group.total_option_stock
    menu_item = option_group.menu_item
    
    if menu_item.stock_quantity != total_option_stock
      menu_item.update_column(:stock_quantity, total_option_stock)
      Rails.logger.info("Synced menu item #{menu_item.id} stock to match option totals: #{total_option_stock}")
    end
  end

  # Validate that option inventory totals match menu item inventory
  def self.validate_inventory_synchronization(menu_item)
    return true unless menu_item.uses_option_level_inventory?
    
    tracking_group = menu_item.option_inventory_tracking_group
    return true unless tracking_group
    
    total_option_stock = tracking_group.total_option_stock
    menu_item_stock = menu_item.stock_quantity.to_i
    
    if total_option_stock != menu_item_stock
      Rails.logger.error("INVENTORY SYNC ERROR: Menu item #{menu_item.id} has #{menu_item_stock} stock but option totals are #{total_option_stock}")
      return false
    end
    
    true
  end

  # Force synchronization by distributing menu item stock across options
  def self.force_synchronize_inventory(menu_item, distribution_strategy = :proportional)
    return false unless menu_item.uses_option_level_inventory?
    
    tracking_group = menu_item.option_inventory_tracking_group
    return false unless tracking_group
    
    menu_item_stock = menu_item.stock_quantity.to_i
    options = tracking_group.options
    
    Rails.logger.info("Force synchronizing inventory for menu item #{menu_item.id} using #{distribution_strategy} strategy")
    
    case distribution_strategy
    when :proportional
      # Distribute proportionally based on current stock ratios
      current_total = tracking_group.total_option_stock
      
      if current_total > 0
        options.each do |option|
          ratio = option.stock_quantity.to_f / current_total
          new_quantity = (menu_item_stock * ratio).round
          option.update_column(:stock_quantity, new_quantity)
          Rails.logger.info("Updated option #{option.id} stock to #{new_quantity} (ratio: #{ratio.round(3)})")
        end
      else
        # Equal distribution if no current stock
        distribute_equally(options, menu_item_stock)
      end
    when :equal
      # Distribute equally across all options
      distribute_equally(options, menu_item_stock)
    end
    
    # Verify synchronization after distribution
    unless validate_inventory_synchronization(menu_item)
      Rails.logger.error("Force synchronization failed for menu item #{menu_item.id}")
      return false
    end
    
    Rails.logger.info("Successfully synchronized inventory for menu item #{menu_item.id}")
    true
  end

  # Check for inventory synchronization issues across all menu items
  def self.audit_inventory_synchronization(restaurant_id = nil)
    issues = []
    
    scope = MenuItem.joins(:option_groups)
                   .where(enable_stock_tracking: true)
                   .where(option_groups: { enable_inventory_tracking: true })
    
    scope = scope.joins(:menu).where(menus: { restaurant_id: restaurant_id }) if restaurant_id
    
    scope.find_each do |menu_item|
      unless validate_inventory_synchronization(menu_item)
        tracking_group = menu_item.option_inventory_tracking_group
        total_option_stock = tracking_group.total_option_stock
        
        issues << {
          menu_item_id: menu_item.id,
          menu_item_name: menu_item.name,
          menu_item_stock: menu_item.stock_quantity.to_i,
          total_option_stock: total_option_stock,
          difference: menu_item.stock_quantity.to_i - total_option_stock,
          option_breakdown: tracking_group.options.pluck(:id, :name, :stock_quantity).map do |id, name, stock|
            { option_id: id, name: name, stock: stock }
          end
        }
      end
    end
    
    if issues.any?
      Rails.logger.warn("Found #{issues.count} inventory synchronization issues")
      issues.each do |issue|
        Rails.logger.warn("Menu item #{issue[:menu_item_id]} (#{issue[:menu_item_name]}): #{issue[:menu_item_stock]} vs #{issue[:total_option_stock]} (diff: #{issue[:difference]})")
      end
    else
      Rails.logger.info("All inventory synchronization checks passed")
    end
    
    issues
  end

  private

  # Helper method to distribute stock equally across options
  def self.distribute_equally(options, total_stock)
    per_option = total_stock / options.count
    remainder = total_stock % options.count
    
    options.each_with_index do |option, index|
      additional = index < remainder ? 1 : 0
      new_quantity = per_option + additional
      option.update_column(:stock_quantity, new_quantity)
      Rails.logger.info("Updated option #{option.id} stock to #{new_quantity} (equal distribution)")
    end
  end
end 