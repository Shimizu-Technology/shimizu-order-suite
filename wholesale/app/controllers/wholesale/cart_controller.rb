# app/controllers/wholesale/cart_controller.rb

module Wholesale
  class CartController < ApplicationController
    # Skip authentication for cart operations - supports both authenticated and anonymous users
    skip_before_action :authorize_request
    before_action :load_cart, except: [:validate]
    before_action :find_item, only: [:add, :update]
    
    # GET /wholesale/cart
    # Get current cart contents
    def show
      render_success(
        cart: cart_summary(@cart),
        message: "Cart retrieved successfully"
      )
    end
    
    # POST /wholesale/cart/add
    # Add item to cart
    def add
      return unless @item
      
      quantity = params[:quantity].to_i
      
      if quantity <= 0
        return render_error("Quantity must be greater than 0")
      end
      
      # Get selected options for variants
      selected_options = params[:selected_options] || {}
      
      # Validate inventory based on tracking type
      inventory_error = validate_inventory_for_add(@item, selected_options, quantity, @cart)
      if inventory_error
        return render_error(inventory_error)
      end
      
      # Check if cart is empty or from same fundraiser
      if @cart.any? && @cart.first[:fundraiser_id] != @item.fundraiser_id
        current_fundraiser = Wholesale::Fundraiser.find(@cart.first[:fundraiser_id])
        return render_error(
          "You can only order from one fundraiser at a time. Please clear your cart or complete your current order from #{current_fundraiser.name}.",
          status: :conflict
        )
      end
      
      # Check if item with same options already exists in cart  
      existing_item = @cart.find { |cart_item| 
        cart_item[:item_id] == @item.id && 
        cart_item[:selected_options] == selected_options.to_h
      }
      
      # Calculate total price including options
      total_price = @item.calculate_price_for_options(selected_options)
      total_price_cents = (total_price * 100).round
      
      if existing_item
        # Update quantity
        new_quantity = existing_item[:quantity] + quantity
        
        unless @item.can_purchase?(new_quantity)
          available = @item.track_inventory? ? @item.available_quantity : "unlimited"
          return render_error("Total quantity exceeds availability. Available: #{available}")
        end
        
        existing_item[:quantity] = new_quantity
        existing_item[:line_total_cents] = new_quantity * total_price_cents
        existing_item[:updated_at] = Time.current
      else
        # Add new item
        @cart << {
          item_id: @item.id,
          fundraiser_id: @item.fundraiser_id,
          name: @item.name,
          description: @item.description,
          sku: @item.sku,
          price_cents: total_price_cents,
          quantity: quantity,
          line_total_cents: quantity * total_price_cents,
          image_url: @item.primary_image_url,
          selected_options: selected_options.to_h,
          added_at: Time.current,
          updated_at: Time.current
        }
      end
      
      save_cart(@cart)
      
      render_success(
        cart: cart_summary(@cart),
        message: "Item added to cart successfully"
      )
    end
    
    # PUT /wholesale/cart/update
    # Update item quantity in cart
    def update
      return unless @item
      
      quantity = params[:quantity].to_i
      
      if quantity < 0
        return render_error("Quantity cannot be negative")
      end
      
      cart_item = @cart.find { |item| item[:item_id] == @item.id }
      
      unless cart_item
        return render_error("Item not found in cart")
      end
      
      if quantity == 0
        # Remove item from cart
        @cart.reject! { |item| item[:item_id] == @item.id }
        message = "Item removed from cart"
      else
        # Check availability
        unless @item.can_purchase?(quantity)
          available = @item.track_inventory? ? @item.available_quantity : "unlimited"
          return render_error("Insufficient stock. Available: #{available}")
        end
        
        # Calculate total price including options
        selected_options = cart_item[:selected_options] || {}
        total_price = @item.calculate_price_for_options(selected_options)
        total_price_cents = (total_price * 100).round
        
        # Update quantity
        cart_item[:quantity] = quantity
        cart_item[:line_total_cents] = quantity * total_price_cents
        cart_item[:updated_at] = Time.current
        message = "Cart updated successfully"
      end
      
      save_cart(@cart)
      
      render_success(
        cart: cart_summary(@cart),
        message: message
      )
    end
    
    # DELETE /wholesale/cart/remove/:item_id
    # Remove specific item from cart
    def remove
      item_id = params[:item_id].to_i
      
      cart_item = @cart.find { |item| item[:item_id] == item_id }
      
      unless cart_item
        return render_error("Item not found in cart")
      end
      
      @cart.reject! { |item| item[:item_id] == item_id }
      save_cart(@cart)
      
      render_success(
        cart: cart_summary(@cart),
        message: "Item removed from cart successfully"
      )
    end
    
    # DELETE /wholesale/cart/clear
    # Clear entire cart
    def clear
      clear_cart
      
      render_success(
        cart: cart_summary([]),
        message: "Cart cleared successfully"
      )
    end
    
    # GET /wholesale/cart/validate
    # Validate cart items (check availability, prices, etc.)
    def validate
      # For validation, we expect cart items to be passed as parameters, not stored in session
      cart_items = params[:cart_items] || []
      
      return render_success(cart: [], valid: true, message: "Empty cart is valid") if cart_items.empty?
      
      issues = []
      valid_cart = []
      
      cart_items.each do |cart_item|
        begin
          item = Wholesale::Item
            .joins(:fundraiser)
            .includes(option_groups: :options)
            .where(fundraiser: { restaurant: current_restaurant })
            .find(cart_item[:item_id])
          
          # Check if item is still active
          unless item.active?
            issues << {
              type: 'item_inactive',
              item_id: item.id,
              item_name: cart_item[:name],
              message: "Item is no longer available"
            }
            next
          end
          
          # Check if fundraiser is still active and current
          unless item.fundraiser.active? && item.fundraiser.current?
            issues << {
              type: 'fundraiser_inactive',
              item_id: item.id,
              item_name: cart_item[:name],
              message: "Fundraiser is no longer accepting orders"
            }
            next
          end
          
          # Check inventory availability (item-level or option-level)
          inventory_issues = validate_cart_item_inventory(item, cart_item)
          issues.concat(inventory_issues)
          
          # Skip further validation if inventory issues found
          next if inventory_issues.any?
          
          # Check if price has changed (including option prices)
          selected_options = cart_item[:selected_options] || {}
          expected_total_price = item.calculate_price_for_options(selected_options)
          expected_price_cents = (expected_total_price * 100).round
          
          if expected_price_cents != cart_item[:price_cents]
            issues << {
              type: 'price_changed',
              item_id: item.id,
              item_name: cart_item[:name],
              old_price: cart_item[:price_cents] / 100.0,
              new_price: expected_total_price,
              message: "Price has changed from $#{cart_item[:price_cents] / 100.0} to $#{expected_total_price}"
            }
            # Update price in cart
            cart_item[:price_cents] = expected_price_cents
            cart_item[:line_total_cents] = cart_item[:quantity] * expected_price_cents
          end
          
          valid_cart << cart_item
          
        rescue ActiveRecord::RecordNotFound
          issues << {
            type: 'item_not_found',
            item_id: cart_item[:item_id],
            item_name: cart_item[:name],
            message: "Item no longer exists"
          }
        end
      end
      
      render_success(
        cart: valid_cart,
        valid: issues.empty?,
        issues: issues,
        message: issues.empty? ? "Cart is valid" : "Cart has #{issues.length} issue(s)"
      )
    end
    
    private
    
    def load_cart
      @cart = get_cart
    end
    
    # Validate inventory for a specific cart item (enhanced for variant tracking)
    def validate_cart_item_inventory(item, cart_item)
      issues = []
      quantity = cart_item[:quantity]
      selected_options = cart_item[:selected_options] || {}
      
      # Check variant-level inventory first (highest priority)
      if item.track_variants?
        return validate_cart_item_variant_inventory(item, cart_item)
      end
      
      # Check item-level inventory if enabled
      if item.track_inventory? && !item.uses_option_level_inventory?
        available = item.available_quantity
        
        if available < quantity
          if available == 0
            issues << {
              type: 'out_of_stock',
              item_id: item.id,
              item_name: cart_item[:name],
              requested: quantity,
              available: available,
              message: "#{cart_item[:name]} is out of stock"
            }
          else
            issues << {
              type: 'insufficient_stock',
              item_id: item.id,
              item_name: cart_item[:name],
              requested: quantity,
              available: available,
              message: "#{cart_item[:name]} only has #{available} available (you have #{quantity} in cart)"
            }
          end
        end
      end
      
      # Check option-level inventory if enabled
      if item.uses_option_level_inventory?
        tracking_group = item.option_inventory_tracking_group
        
        if tracking_group && selected_options.present?
          # Parse selected options - they could be stored as JSON string or hash
          parsed_options = case selected_options
          when String
            begin
              JSON.parse(selected_options)
            rescue JSON::ParserError
              {}
            end
          when ActionController::Parameters
            selected_options.to_unsafe_h
          when Hash
            selected_options
          else
            {}
          end
          
          # Get selected options for the tracking group
          group_selections = parsed_options[tracking_group.id.to_s] || []
          group_selections = Array(group_selections)
          
          group_selections.each do |option_id|
            option = tracking_group.options.find_by(id: option_id)
            next unless option
            
            # Check if option is marked as unavailable
            unless option.available
              issues << {
                type: 'option_unavailable',
                item_id: item.id,
                item_name: cart_item[:name],
                option_id: option.id,
                option_name: option.name,
                requested: quantity,
                available: 0,
                message: "#{option.name} is no longer available (from #{cart_item[:name]})"
              }
              next
            end
            
            available = option.available_stock
            
            if available < quantity
              option_display_name = "#{cart_item[:name]} (#{option.name})"
              
              if available == 0
                issues << {
                  type: 'out_of_stock',
                  item_id: item.id,
                  item_name: cart_item[:name],
                  option_id: option.id,
                  option_name: option.name,
                  requested: quantity,
                  available: available,
                  message: "#{option_display_name} is out of stock"
                }
              else
                issues << {
                  type: 'insufficient_stock',
                  item_id: item.id,
                  item_name: cart_item[:name],
                  option_id: option.id,
                  option_name: option.name,
                  requested: quantity,
                  available: available,
                  message: "#{option_display_name} only has #{available} available (you have #{quantity} in cart)"
                }
              end
            end
          end
        end
      end
      
      # Check for unavailable options in non-inventory-tracked option groups
      if item.has_options? && selected_options.present?
        # Parse selected options - they could be stored as JSON string or hash
        parsed_options = case selected_options
        when String
          begin
            JSON.parse(selected_options)
          rescue JSON::ParserError
            {}
          end
        when ActionController::Parameters
          selected_options.to_unsafe_h
        when Hash
          selected_options
        else
          {}
        end
        
        item.option_groups.includes(:options).each do |group|
          # Skip if this is the inventory tracking group (already handled above)
          next if item.uses_option_level_inventory? && group == item.option_inventory_tracking_group
          
          group_selections = parsed_options[group.id.to_s] || []
          group_selections = Array(group_selections)
          
          group_selections.each do |option_id|
            option = group.options.find_by(id: option_id)
            next unless option
            
            # Check if option is marked as unavailable
            unless option.available
              issues << {
                type: 'option_unavailable',
                item_id: item.id,
                item_name: cart_item[:name],
                option_id: option.id,
                option_name: option.name,
                group_name: group.name,
                requested: quantity,
                available: 0,
                message: "#{option.name} is no longer available for #{group.name} (from #{cart_item[:name]})"
              }
            end
          end
        end
      end
      
      issues
    end
    
    def find_item
      item_id = params[:item_id] || params[:id]
      @item = Wholesale::Item
        .joins(:fundraiser)
        .where(fundraiser: { restaurant: current_restaurant, active: true })
        .merge(Wholesale::Fundraiser.current)
        .find(item_id)
    rescue ActiveRecord::RecordNotFound
      render_not_found("Item not found")
      nil
    end
    
    def get_cart
      if current_user
        # User-based cart (stored in database or session with user ID)
        session["wholesale_cart_#{current_user.id}"] ||= []
      else
        # Session-based cart for anonymous users
        session[:wholesale_cart] ||= []
      end
    end
    
    def save_cart(cart)
      if current_user
        session["wholesale_cart_#{current_user.id}"] = cart
      else
        session[:wholesale_cart] = cart
      end
    end
    
    def clear_cart
      if current_user
        session.delete("wholesale_cart_#{current_user.id}")
      else
        session.delete(:wholesale_cart)
      end
    end
    
    def cart_summary(cart)
      return empty_cart_summary if cart.empty?
      
      # Get fundraiser info
      fundraiser_id = cart.first[:fundraiser_id]
      fundraiser = Wholesale::Fundraiser.find(fundraiser_id)
      
      total_cents = cart.sum { |item| item[:line_total_cents] }
      total_quantity = cart.sum { |item| item[:quantity] }
      
      {
        items: cart.map do |cart_item|
          {
            item_id: cart_item[:item_id],
            name: cart_item[:name],
            description: cart_item[:description],
            sku: cart_item[:sku],
            price: cart_item[:price_cents] / 100.0,
            price_cents: cart_item[:price_cents],
            quantity: cart_item[:quantity],
            line_total: cart_item[:line_total_cents] / 100.0,
            line_total_cents: cart_item[:line_total_cents],
            image_url: cart_item[:image_url],
            added_at: cart_item[:added_at],
            updated_at: cart_item[:updated_at]
          }
        end,
        
        fundraiser: {
          id: fundraiser.id,
          name: fundraiser.name,
          slug: fundraiser.slug
        },
        
        totals: {
          item_count: cart.length,
          total_quantity: total_quantity,
          subtotal: total_cents / 100.0,
          subtotal_cents: total_cents,
          # Note: Tax and shipping would be calculated at checkout
        },
        
        cart_url: "/wholesale/cart",
        checkout_url: "/wholesale/checkout"
      }
    end
    
    def empty_cart_summary
      {
        items: [],
        fundraiser: nil,
        totals: {
          item_count: 0,
          total_quantity: 0,
          subtotal: 0.0,
          subtotal_cents: 0
        },
        cart_url: "/wholesale/cart",
        checkout_url: "/wholesale/checkout"
      }
    end
    
    # Validate inventory for adding items to cart (enhanced for variant tracking)
    def validate_inventory_for_add(item, selected_options, quantity, cart)
      # Check variant tracking first (highest priority)
      if item.track_variants?
        return validate_variant_inventory_for_add(item, selected_options, quantity, cart)
      end
      
      # Fall back to existing validation methods
      return nil unless item.track_inventory? || item.uses_option_level_inventory?
      
      if item.uses_option_level_inventory?
        # Option-level inventory validation
        validate_option_inventory_for_add(item, selected_options, quantity, cart)
      else
        # Item-level inventory validation
        validate_item_inventory_for_add(item, quantity, cart)
      end
    end
    
    # Validate item-level inventory for adding to cart
    def validate_item_inventory_for_add(item, quantity, cart)
      # Calculate existing quantity of this item in cart (across all option combinations)
      existing_cart_quantity = cart.select { |cart_item| cart_item[:item_id] == item.id }
                                   .sum { |cart_item| cart_item[:quantity] }
      
      # Check total quantity (existing + new) against available inventory
      total_quantity = existing_cart_quantity + quantity
      unless item.can_purchase?(total_quantity)
        available = item.available_quantity
        if existing_cart_quantity > 0
          return "Total quantity would exceed availability. You have #{existing_cart_quantity} in cart, trying to add #{quantity} more. Available: #{available}"
        else
          return "Insufficient stock. Available: #{available}"
        end
      end
      
      nil # No error
    end
    
    # Validate option-level inventory for adding to cart
    def validate_option_inventory_for_add(item, selected_options, quantity, cart)
      tracking_group = item.option_inventory_tracking_group
      return nil unless tracking_group
      
      # Get selected options for the tracking group
      tracking_group_selections = selected_options[tracking_group.id.to_s]
      return nil if tracking_group_selections.blank?
      
      # Check each selected option
      Array(tracking_group_selections).each do |option_id|
        option = tracking_group.options.active.find_by(id: option_id)
        next unless option
        
        # Calculate existing quantity of this specific option in cart
        existing_option_quantity = cart.select do |cart_item|
          cart_item[:item_id] == item.id &&
          cart_item[:selected_options] &&
          cart_item[:selected_options][tracking_group.id.to_s] &&
          Array(cart_item[:selected_options][tracking_group.id.to_s]).include?(option_id.to_i)
        end.sum { |cart_item| cart_item[:quantity] }
        
        # Check total quantity for this option
        total_option_quantity = existing_option_quantity + quantity
        available = option.available_stock
        
        unless available >= total_option_quantity
          if existing_option_quantity > 0
            return "Total quantity would exceed availability for #{option.name}. You have #{existing_option_quantity} in cart, trying to add #{quantity} more. Available: #{available}"
          else
            return "Insufficient stock for #{option.name}. Available: #{available}"
          end
        end
      end
      
      nil # No error
    end
    
    # Validate variant-level inventory for adding to cart
    def validate_variant_inventory_for_add(item, selected_options, quantity, cart)
      return "No options selected for variant-tracked item" if selected_options.blank?
      
      # Generate variant key from selected options
      variant_key = item.generate_variant_key(selected_options)
      return "Invalid option combination" if variant_key.blank?
      
      # Find the specific variant
      variant = item.find_variant_by_options(selected_options)
      unless variant
        variant_name = item.generate_variant_name(selected_options)
        return "#{variant_name || 'This combination'} is not available for #{item.name}"
      end
      
      # Check if variant is active
      unless variant.active?
        return "#{variant.variant_name} is no longer available"
      end
      
      # Calculate existing quantity of this specific variant in cart
      existing_variant_quantity = cart.select do |cart_item|
        cart_item[:item_id] == item.id &&
        cart_item[:selected_options] &&
        item.generate_variant_key(cart_item[:selected_options]) == variant_key
      end.sum { |cart_item| cart_item[:quantity] }
      
      # Check total quantity for this variant
      total_variant_quantity = existing_variant_quantity + quantity
      available = variant.available_stock
      
      unless available >= total_variant_quantity
        if existing_variant_quantity > 0
          return "Total quantity would exceed availability for #{variant.variant_name}. You have #{existing_variant_quantity} in cart, trying to add #{quantity} more. Available: #{available}"
        else
          if available == 0
            return "#{variant.variant_name} is out of stock"
          else
            return "#{variant.variant_name} has only #{available} available (you're trying to add #{quantity})"
          end
        end
      end
      
      nil # No error
    end
    
    # Validate variant-level inventory for a specific cart item
    def validate_cart_item_variant_inventory(item, cart_item)
      issues = []
      quantity = cart_item[:quantity]
      selected_options = cart_item[:selected_options] || {}
      
      # Parse selected options - they could be stored as JSON string or hash
      parsed_options = case selected_options
      when String
        begin
          JSON.parse(selected_options)
        rescue JSON::ParserError
          {}
        end
      when ActionController::Parameters
        selected_options.to_unsafe_h
      when Hash
        selected_options
      else
        {}
      end
      
      if parsed_options.blank?
        issues << {
          type: 'variant_no_options',
          item_id: item.id,
          item_name: cart_item[:name],
          requested: quantity,
          available: 0,
          message: "No options selected for variant-tracked item #{cart_item[:name]}"
        }
        return issues
      end
      
      # Generate variant key from selected options
      variant_key = item.generate_variant_key(parsed_options)
      if variant_key.blank?
        issues << {
          type: 'variant_invalid_options',
          item_id: item.id,
          item_name: cart_item[:name],
          requested: quantity,
          available: 0,
          message: "Invalid option combination for #{cart_item[:name]}"
        }
        return issues
      end
      
      # Find the specific variant
      variant = item.find_variant_by_options(parsed_options)
      unless variant
        variant_name = item.generate_variant_name(parsed_options)
        issues << {
          type: 'variant_not_found',
          item_id: item.id,
          item_name: cart_item[:name],
          variant_key: variant_key,
          variant_name: variant_name,
          requested: quantity,
          available: 0,
          message: "#{variant_name || 'This combination'} is not available for #{cart_item[:name]}"
        }
        return issues
      end
      
      # Check if variant is active
      unless variant.active?
        issues << {
          type: 'variant_inactive',
          item_id: item.id,
          item_name: cart_item[:name],
          variant_id: variant.id,
          variant_key: variant.variant_key,
          variant_name: variant.variant_name,
          requested: quantity,
          available: 0,
          message: "#{variant.variant_name} is no longer available"
        }
        return issues
      end
      
      # Check variant stock availability
      available = variant.available_stock
      
      if available < quantity
        if available == 0
          issues << {
            type: 'variant_out_of_stock',
            item_id: item.id,
            item_name: cart_item[:name],
            variant_id: variant.id,
            variant_key: variant.variant_key,
            variant_name: variant.variant_name,
            requested: quantity,
            available: available,
            message: "#{variant.variant_name} is out of stock"
          }
        else
          issues << {
            type: 'variant_insufficient_stock',
            item_id: item.id,
            item_name: cart_item[:name],
            variant_id: variant.id,
            variant_key: variant.variant_key,
            variant_name: variant.variant_name,
            requested: quantity,
            available: available,
            message: "#{variant.variant_name} only has #{available} available (you have #{quantity} in cart)"
          }
        end
      end
      
      issues
    end
  end
end