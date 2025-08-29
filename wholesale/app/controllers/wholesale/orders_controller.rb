# app/controllers/wholesale/orders_controller.rb

module Wholesale
  class OrdersController < ApplicationController
    # Allow guest checkout for order creation (like regular orders)
      skip_before_action :authorize_request, only: [:create, :show]
  before_action :optional_authorize, only: [:create, :show]
    before_action :find_order, only: [:show, :update, :cancel]
    
    # GET /wholesale/orders
    # List user's orders
    def index
      @orders = Wholesale::Order
        .where(restaurant: current_restaurant, user: current_user)
        .includes(:fundraiser, :participant, :order_items, :order_payments)
        .order(created_at: :desc)
      
      # Optional filtering
      @orders = @orders.where(status: params[:status]) if params[:status].present?
      @orders = @orders.joins(:fundraiser).where(fundraiser: { slug: params[:fundraiser_slug] }) if params[:fundraiser_slug].present?
      
      render_success(
        orders: @orders.map { |order| order_summary(order) },
        message: "Orders retrieved successfully"
      )
    end
    
    # GET /wholesale/orders/:id
    # Get specific order details
    def show
      render_success(
        order: order_detail(@order),
        message: "Order details retrieved successfully"
      )
    end
    
    # POST /wholesale/orders
    # Create new order from cart (checkout)
    def create
      # Get cart items from request parameters (like regular orders)
      cart_items = params[:cart_items] || []
      
      if cart_items.empty?
        return render_error("Cart is empty")
      end
      
      # Validate required parameters (accept both snake_case and camelCase from frontend)
      order_params = normalized_order_params
      
      if order_params[:customer_name].blank? || order_params[:customer_email].blank?
        return render_error("Customer name and email are required")
      end
      
      begin
        ActiveRecord::Base.transaction do
          # Create the order
          fundraiser_id = cart_items.first['fundraiser_id'] || cart_items.first[:fundraiser_id]
          fundraiser = Wholesale::Fundraiser.find(fundraiser_id)
          # Ensure fundraiser is active and currently running
          unless fundraiser.active? && fundraiser.current?
            raise "Fundraiser is not currently accepting orders"
          end
          
          # Validate participant if specified
          participant = nil
          if order_params[:participant_id].present?
            participant = fundraiser.participants.active.find(order_params[:participant_id])
          end
          
          # Calculate totals
          subtotal_cents = cart_items.sum { |item| (item['line_total_cents'] || item[:line_total_cents]).to_i }
          
          # Generate fundraiser-specific order number
          order_number = Wholesale::FundraiserCounter.next_order_number(fundraiser.id)
          
          @order = Wholesale::Order.create!(
            restaurant: current_restaurant,
            fundraiser: fundraiser,
            user: current_user,
            participant: participant,
            order_number: order_number, # Set order number explicitly
            customer_name: order_params[:customer_name],
            customer_email: order_params[:customer_email],
            customer_phone: order_params[:customer_phone],
            shipping_address: order_params[:shipping_address],
            total_cents: subtotal_cents,
            notes: order_params[:notes],
            status: 'pending' # Orders start as pending, payment processing will update to 'paid'
          )
          
          # Create order items
          cart_items.each do |cart_item|
            item_id = cart_item['item_id'] || cart_item[:item_id]
             item = Wholesale::Item.find(item_id)
             # Additional safety: ensure item belongs to the same active/current fundraiser
             unless item.fundraiser_id == fundraiser.id && fundraiser.active? && fundraiser.current?
               raise "Fundraiser is not currently accepting orders"
             end
             
             # Ensure item is still active
             unless item.active?
               raise "Item #{item.name} is no longer available"
             end
            
            quantity = (cart_item['quantity'] || cart_item[:quantity]).to_i
            # Validate availability one more time
            unless item.can_purchase?(quantity)
              raise "Item #{item.name} is no longer available in the requested quantity"
            end
            
            @order.order_items.create!(
              item: item,
              quantity: quantity,
              price_cents: (cart_item['price_cents'] || cart_item[:price_cents]).to_i,
              item_name: cart_item['name'] || cart_item[:name],
              item_description: cart_item['description'] || cart_item[:description],
              selected_options: cart_item['selected_options'] || cart_item[:selected_options] || {}
            )
          end
          
          # Reduce inventory
          @order.reduce_inventory!
          
          # Send confirmations for wholesale orders (they're order requests, not immediate payments)
          send_order_confirmations(@order)
          
          # No need to clear cart - frontend manages cart state
          
          render_success(
            order: order_detail(@order),
            message: "Order created successfully",
            status: :created
          )
        end
        
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Order validation failed: #{e.record.errors.full_messages}")
        Rails.logger.error("Order attributes: #{e.record.attributes}")
        
        # Check if it's an inventory-related validation error
        error_messages = e.record.errors.full_messages
        inventory_errors = error_messages.select do |msg|
          msg.include?('out of stock') || 
          msg.include?('only') && msg.include?('available') ||
          msg.include?('insufficient') ||
          msg.include?('no longer available')
        end
        
        if inventory_errors.any?
          # Try to get more specific information from cart validation
          begin
            # Validate the current cart to get detailed inventory issues
            cart_validation = validate_current_cart_items
            
            if cart_validation[:issues].any?
              specific_errors = cart_validation[:issues].map do |issue|
                case issue[:type]
                when 'out_of_stock'
                  "#{issue[:item_name]}#{issue[:option_name] ? " (#{issue[:option_name]})" : ""} is no longer available"
                when 'insufficient_stock'
                  "#{issue[:item_name]}#{issue[:option_name] ? " (#{issue[:option_name]})" : ""} only has #{issue[:available]} available (you're trying to order #{issue[:requested]})"
                when 'option_unavailable'
                  "#{issue[:option_name]} is no longer available#{issue[:group_name] ? " for #{issue[:group_name]}" : ""} (from #{issue[:item_name]})"
                when 'item_not_found'
                  "#{issue[:item_name]} is no longer available"
                else
                  issue[:message] || "Unknown inventory issue"
                end
              end
              
              render_error("The following items in your cart have inventory issues:\n\n#{specific_errors.join('\n')}\n\nPlease update your cart and try again.")
            else
              # Fallback to generic message
              render_error("Sorry, some items in your cart are no longer available in the requested quantity. Please refresh your cart and try again.")
            end
          rescue => validation_error
            Rails.logger.error("Failed to validate cart for detailed error: #{validation_error.message}")
            # Fallback to generic message
            render_error("Sorry, some items in your cart are no longer available in the requested quantity. Please refresh your cart and try again.")
          end
        else
          # Generic validation error
          render_error("Order validation failed: #{error_messages.join(', ')}")
        end
      rescue ActiveRecord::StatementInvalid => e
        # Handle database constraint violations (like negative stock)
        if e.message.include?('check_options_stock_quantity_non_negative') || 
           e.message.include?('stock_quantity') && e.message.include?('constraint')
          Rails.logger.warn("Inventory constraint violation during order creation: #{e.message}")
          render_error("Sorry, some items in your cart are no longer available in the requested quantity. Please refresh and try again.")
        else
          Rails.logger.error("Database error during order creation: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          render_error("Order creation failed due to a database error. Please try again.")
        end
      rescue StandardError => e
        # Check if it's an inventory-related error from our custom validations
        if e.message.include?('Insufficient stock') || e.message.include?('no longer available')
          Rails.logger.warn("Inventory validation failed during order creation: #{e.message}")
          render_error("Sorry, some items in your cart are no longer available in the requested quantity. Please refresh your cart and try again.")
        else
          Rails.logger.error("Order creation failed: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          render_error("Order creation failed: #{e.message}")
        end
      end
    end
    
    # NOTE: keep actions public until after :status, then switch to private helpers
    # Accepts both camelCase (from some frontends) and snake_case keys
    def normalized_order_params
      raw = params.require(:order).permit(
        :customer_name, :customer_email, :customer_phone,
        :shipping_address, :notes, :participant_id,
        :customerName, :customerEmail, :customerPhone,
        :shippingAddress, :participantId
      )

      {
        customer_name: raw[:customer_name].presence || raw[:customerName],
        customer_email: raw[:customer_email].presence || raw[:customerEmail],
        customer_phone: raw[:customer_phone].presence || raw[:customerPhone],
        shipping_address: raw[:shipping_address].presence || raw[:shippingAddress],
        notes: raw[:notes],
        participant_id: raw[:participant_id].presence || raw[:participantId]
      }
    end

    # PUT /wholesale/orders/:id
    # Update order (limited updates allowed)
    def update
      # Only allow updates for pending orders
      unless @order.pending?
        return render_error("Order cannot be modified in current status: #{@order.status}")
      end
      
      update_params = params.require(:order).permit(
        :customer_name, :customer_email, :customer_phone,
        :shipping_address, :notes
      )
      
      if @order.update(update_params)
        render_success(
          order: order_detail(@order),
          message: "Order updated successfully"
        )
      else
        render_error("Order update failed", errors: @order.errors.full_messages)
      end
    end
    
    # DELETE /wholesale/orders/:id/cancel
    # Cancel order
    def cancel
      unless @order.can_be_cancelled?
        return render_error("Order cannot be cancelled in current status: #{@order.status}")
      end
      
      if @order.cancel!
        render_success(
          order: order_detail(@order),
          message: "Order cancelled successfully"
        )
      else
        render_error("Order cancellation failed")
      end
    end
    
    # GET /wholesale/orders/:id/status
    # Get order status and tracking info
    def status
      find_order
      
      render_success(
        order_id: @order.id,
        order_number: @order.order_number,
        status: @order.status,
        created_at: @order.created_at,
        total: @order.total,
        customer_name: @order.customer_name,
        fundraiser: {
          name: @order.fundraiser.name,
          slug: @order.fundraiser.slug,
          pickup_display_name: @order.fundraiser.pickup_display_name,
          pickup_display_address: @order.fundraiser.pickup_display_address,
          pickup_instructions: @order.fundraiser.pickup_instructions,
          pickup_contact_name: @order.fundraiser.pickup_contact_name,
          pickup_contact_phone: @order.fundraiser.pickup_contact_display_phone,
          pickup_hours: @order.fundraiser.pickup_hours
        },
        participant: @order.participant ? {
          name: @order.participant.name,
          slug: @order.participant.slug
        } : nil,
        payment_status: @order.payment_complete? ? 'completed' : 'pending',
        message: "Order status retrieved successfully"
      )
    end
    
    private
    
    # Validate cart items to get detailed inventory issues
    def validate_current_cart_items
      cart_items = params[:cart_items] || []
      issues = []
      
      cart_items.each do |cart_item_params|
        begin
          item = Wholesale::Item
            .joins(:fundraiser)
            .includes(option_groups: :options)
            .where(fundraiser: { restaurant: current_restaurant })
            .find(cart_item_params[:item_id])
          
          quantity = cart_item_params[:quantity].to_i
          selected_options = cart_item_params[:selected_options] || {}
          
          # Check item-level inventory if enabled
          if item.track_inventory? && !item.uses_option_level_inventory?
            available = item.available_quantity
            
            if available < quantity
              if available == 0
                issues << {
                  type: 'out_of_stock',
                  item_id: item.id,
                  item_name: cart_item_params[:name] || item.name,
                  requested: quantity,
                  available: available
                }
              else
                issues << {
                  type: 'insufficient_stock',
                  item_id: item.id,
                  item_name: cart_item_params[:name] || item.name,
                  requested: quantity,
                  available: available
                }
              end
            end
          end
          
          # Check option-level inventory if enabled
          if item.uses_option_level_inventory?
            tracking_group = item.option_inventory_tracking_group
            
            if tracking_group && selected_options.present?
              # Get selected options for the tracking group
              group_selections = selected_options[tracking_group.id.to_s] || []
              group_selections = Array(group_selections)
              
              group_selections.each do |option_id|
                option = tracking_group.options.find_by(id: option_id)
                next unless option
                
                # Check if option is marked as unavailable
                unless option.available
                  issues << {
                    type: 'option_unavailable',
                    item_id: item.id,
                    item_name: cart_item_params[:name] || item.name,
                    option_id: option.id,
                    option_name: option.name,
                    requested: quantity,
                    available: 0
                  }
                  next
                end
                
                available = option.available_stock
                
                if available < quantity
                  if available == 0
                    issues << {
                      type: 'out_of_stock',
                      item_id: item.id,
                      item_name: cart_item_params[:name] || item.name,
                      option_id: option.id,
                      option_name: option.name,
                      requested: quantity,
                      available: available
                    }
                  else
                    issues << {
                      type: 'insufficient_stock',
                      item_id: item.id,
                      item_name: cart_item_params[:name] || item.name,
                      option_id: option.id,
                      option_name: option.name,
                      requested: quantity,
                      available: available
                    }
                  end
                end
              end
            end
          end
          
          # Check for unavailable options in non-inventory-tracked option groups
          if item.has_options? && selected_options.present?
            item.option_groups.includes(:options).each do |group|
              # Skip if this is the inventory tracking group (already handled above)
              next if item.uses_option_level_inventory? && group == item.option_inventory_tracking_group
              
              group_selections = selected_options[group.id.to_s] || []
              group_selections = Array(group_selections)
              
              group_selections.each do |option_id|
                option = group.options.find_by(id: option_id)
                next unless option
                
                # Check if option is marked as unavailable
                unless option.available
                  issues << {
                    type: 'option_unavailable',
                    item_id: item.id,
                    item_name: cart_item_params[:name] || item.name,
                    option_id: option.id,
                    option_name: option.name,
                    group_name: group.name,
                    requested: quantity,
                    available: 0
                  }
                end
              end
            end
          end
          
        rescue ActiveRecord::RecordNotFound
          issues << {
            type: 'item_not_found',
            item_id: cart_item_params[:item_id],
            item_name: cart_item_params[:name] || 'Unknown item'
          }
        end
      end
      
      { issues: issues, valid: issues.empty? }
    end
    
    def get_payment_configuration
      # Get payment settings from restaurant configuration
      payment_gateway = current_restaurant.admin_settings&.dig('payment_gateway')
      
      return nil unless payment_gateway&.dig('payment_processor') == 'stripe'
      
      {
        publishable_key: payment_gateway['publishable_key'],
        secret_key: payment_gateway['secret_key'],
        webhook_secret: payment_gateway['webhook_secret'],
        test_mode: payment_gateway['test_mode'] || false
      }
    end
    
    def send_order_confirmations(order)
      # Get notification preferences - both email and SMS are enabled by default for better UX
      # Users must explicitly set email: false or sms: false to disable notifications
      notification_channels = current_restaurant.admin_settings&.dig("notification_channels", "wholesale_orders") || {}
      restaurant_name = current_restaurant.name
      
      # 1) Confirmation email (to the customer) - enabled by default unless explicitly disabled
      if notification_channels["email"] != false && order.customer_email.present?
        WholesaleOrderMailer.order_confirmation(order).deliver_later
        Rails.logger.info("Wholesale order confirmation email queued for order ##{order.order_number}")
      end
      
      # 2) POC notification email (to the fundraiser contact) - only if contact email exists
      if order.fundraiser.contact_email.present?
        WholesaleOrderMailer.poc_order_notification(order).deliver_later
        Rails.logger.info("Wholesale POC notification email queued for order ##{order.order_number} to #{order.fundraiser.contact_email}")
      end
      
      # 3) Confirmation SMS (to the customer) - enabled by default unless explicitly disabled
      if notification_channels["sms"] != false && order.customer_phone.present?
        # Priority: 1) Fundraiser contact phone, 2) Restaurant phone, 3) Admin SMS sender ID, 4) Restaurant name
        sms_sender = order.fundraiser.contact_phone.presence ||
                     current_restaurant.phone_number.presence ||
                     current_restaurant.admin_settings&.dig("sms_sender_id").presence ||
                     restaurant_name
        
        # Format phone numbers for ClickSend (remove dashes, keep only digits)
        if sms_sender&.match?(/^[\+\d\-\s\(\)]+$/) && sms_sender.gsub(/\D/, '').length >= 10
          sms_sender = sms_sender.gsub(/\D/, '').gsub(/^1/, '')
        end
        
        participant_text = order.participant ? " supporting #{order.participant.name}" : ""
        
        # Build item list for SMS (similar to regular orders)
        item_list = order.order_items.map { |item| "#{item.quantity}x #{item.item_name}" }.join(", ")
        
        # Build pickup info for SMS
        pickup_info = if order.fundraiser.pickup_display_name.present?
          " Pickup at #{order.fundraiser.pickup_display_name}"
        else
          ""
        end
        
        message_body = <<~MSG.squish
          Hi #{order.customer_name}, thanks for supporting #{order.fundraiser.name}#{participant_text}!
          Wholesale Order ##{order.order_number}: #{item_list},
          total: $#{'%.2f' % (order.total_cents / 100.0)}.#{pickup_info}
          Check email for full pickup details!
        MSG
        
        SendSmsJob.perform_later(
          to: order.customer_phone,
          body: message_body,
          from: sms_sender
        )
        Rails.logger.info("Wholesale order SMS confirmation queued for order ##{order.order_number}")
      end
    end
    
    def find_order
      @order = Wholesale::Order
        .where(restaurant: current_restaurant, user: current_user)
        .includes(:fundraiser, :participant, :order_items, :order_payments)
        .find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_not_found("Order not found")
      nil
    end
    

    
    def order_summary(order)
      {
        id: order.id,
        order_number: order.order_number,
        status: order.status,
        customer_name: order.customer_name,
        customer_email: order.customer_email,
        total: order.total,
        total_cents: order.total_cents,
        item_count: order.item_count,
        unique_item_count: order.unique_item_count,
        
        fundraiser: {
          id: order.fundraiser.id,
          name: order.fundraiser.name,
          slug: order.fundraiser.slug,
          pickup_display_name: order.fundraiser.pickup_display_name,
          pickup_display_address: order.fundraiser.pickup_display_address,
          pickup_instructions: order.fundraiser.pickup_instructions,
          pickup_contact_name: order.fundraiser.pickup_contact_name,
          pickup_contact_phone: order.fundraiser.pickup_contact_display_phone,
          pickup_hours: order.fundraiser.pickup_hours
        },
        
        participant: order.participant ? {
          id: order.participant.id,
          name: order.participant.name,
          slug: order.participant.slug
        } : nil,
        
        payment_status: order.payment_complete? ? 'completed' : 'pending',
        total_paid: order.total_paid,
        
        created_at: order.created_at,
        updated_at: order.updated_at
      }
    end
    
    def order_detail(order)
      {
        id: order.id,
        orderNumber: order.order_number,
        status: order.status,
        customerName: order.customer_name,
        customerEmail: order.customer_email,
        customerPhone: order.customer_phone,
        shippingAddress: order.shipping_address,
        notes: order.notes,
        
        total: order.total,
        totalCents: order.total_cents,
        subtotal: order.subtotal,
        subtotalCents: order.subtotal_cents,
        
        itemCount: order.item_count,
        uniqueItemCount: order.unique_item_count,
        
        # Order items
        items: order.order_items.includes(:item).map do |order_item|
          {
            id: order_item.id,
            item_id: order_item.item_id,
            name: order_item.item_name,
            description: order_item.item_description,
            quantity: order_item.quantity,
            price: order_item.price,
            price_cents: order_item.price_cents,
            line_total_cents: order_item.line_total_cents,
            selected_options: order_item.selected_options,
            variant_description: order_item.variant_description,
            
            # Current item info (may differ from order snapshot)
            current_item: order_item.item ? {
              name: order_item.item.name,
              price: order_item.item.price,
              active: order_item.item.active?,
              primary_image_url: order_item.item.primary_image_url
            } : nil
          }
        end,
        
        # Fundraiser details
        fundraiser: {
          id: order.fundraiser.id,
          name: order.fundraiser.name,
          slug: order.fundraiser.slug,
          description: order.fundraiser.description,
          contact_email: order.fundraiser.contact_email,
          contact_phone: order.fundraiser.contact_phone,
          pickup_display_name: order.fundraiser.pickup_display_name,
          pickup_display_address: order.fundraiser.pickup_display_address,
          pickup_instructions: order.fundraiser.pickup_instructions,
          pickup_contact_name: order.fundraiser.pickup_contact_name,
          pickup_contact_phone: order.fundraiser.pickup_contact_display_phone,
          pickup_hours: order.fundraiser.pickup_hours
        },
        
        # Participant details
        participant: order.participant ? {
          id: order.participant.id,
          name: order.participant.name,
          slug: order.participant.slug,
          description: order.participant.description,
          photo_url: order.participant.photo_url
        } : nil,
        
        # Payment information
        paymentStatus: case order.status
        when 'pending' then 'pending'
        when 'paid', 'fulfilled', 'completed' then 'paid'
        when 'cancelled' then 'cancelled'
        else 'pending'
        end,
        totalPaid: order.total_paid,
        totalPaidCents: order.total_paid_cents,
        paymentPending: order.payment_pending?,
        
        payments: order.order_payments.recent.map do |payment|
          {
            id: payment.id,
            amount: payment.amount,
            amountCents: payment.amount_cents,
            paymentMethod: payment.payment_method,
            status: payment.status,
            processedAt: payment.processed_at,
            createdAt: payment.created_at
          }
        end,
        
        # Status helpers
        canBeCancelled: order.can_be_cancelled?,
        canBeRefunded: order.can_be_refunded?,
        
        createdAt: order.created_at,
        updatedAt: order.updated_at
      }
    end
  end
end