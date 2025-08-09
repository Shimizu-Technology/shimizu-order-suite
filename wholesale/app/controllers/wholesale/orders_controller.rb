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
        render_error("Order validation failed: #{e.record.errors.full_messages.join(', ')}")
      rescue StandardError => e
        Rails.logger.error("Order creation failed: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render_error("Order creation failed: #{e.message}")
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
      # Get notification preferences (consistent with regular orders)
      notification_channels = current_restaurant.admin_settings&.dig("notification_channels", "wholesale_orders") || {}
      restaurant_name = current_restaurant.name
      
      # 1) Confirmation email (to the customer) - enabled by default unless explicitly disabled
      if notification_channels["email"] != false && order.customer_email.present?
        WholesaleOrderMailer.order_confirmation(order).deliver_later
        Rails.logger.info("Wholesale order confirmation email queued for order ##{order.order_number}")
      end
      
      # 2) Confirmation SMS (to the customer) - must be explicitly enabled (consistent with regular orders)
      if notification_channels["sms"] == true && order.customer_phone.present?
        sms_sender = current_restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name
        
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