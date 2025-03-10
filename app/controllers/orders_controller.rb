# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :authorize_request, except: [:create, :show]
  
  # Mark create, show, new_since, index, update, and destroy as public endpoints that don't require restaurant context
  def public_endpoint?
    action_name.in?(['create', 'show', 'new_since', 'index', 'update', 'destroy', 'acknowledge', 'unacknowledged'])
  end

  # GET /orders
  def index
    if current_user&.role.in?(%w[admin super_admin])
      @orders = Order.all
    elsif current_user
      @orders = current_user.orders
    else
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end
    
    # Add pagination
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 5).to_i
    
    # Get total count before pagination
    total_count = @orders.count
    
    # Apply sorting and pagination
    @orders = @orders.order(created_at: :desc)
                    .offset((page - 1) * per_page)
                    .limit(per_page)
    
    render json: {
      orders: @orders,
      total_count: total_count,
      page: page,
      per_page: per_page
    }, status: :ok
  end

  # GET /orders/:id
  def show
    order = Order.find(params[:id])
    if current_user&.role.in?(%w[admin super_admin]) ||
       (current_user && current_user.id == order.user_id)
      render json: order
    else
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end

  # GET /orders/new_since/:id
  def new_since
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    last_id = params[:id].to_i
    new_orders = Order.where("id > ?", last_id).order(:id)
    render json: new_orders, status: :ok
  end
  
  # GET /orders/unacknowledged
  def unacknowledged
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Forbidden" }, status: :forbidden
    end
    
    # Get time threshold (default to 24 hours ago)
    hours = params[:hours].present? ? params[:hours].to_i : 24
    time_threshold = Time.current - hours.hours
    
    # Find orders that:
    # 1. Are newer than the time threshold
    # 2. Haven't been acknowledged by the current user
    unacknowledged_orders = Order.where('created_at > ?', time_threshold)
                                 .where.not(id: current_user.acknowledged_orders.pluck(:id))
                                 .order(created_at: :desc)
    
    render json: unacknowledged_orders, status: :ok
  end
  
  # POST /orders/:id/acknowledge
  def acknowledge
    order = Order.find(params[:id])
    
    # Create acknowledgment record
    acknowledgment = OrderAcknowledgment.find_or_initialize_by(
      order: order,
      user: current_user
    )
    
    if acknowledgment.new_record? && acknowledgment.save
      render json: { message: "Order #{order.id} acknowledged" }, status: :ok
    else
      render json: { error: "Failed to acknowledge order" }, status: :unprocessable_entity
    end
  end

  # POST /orders
  def create
    # Optional decode of JWT for user lookup, treat as guest if invalid
    if request.headers['Authorization'].present?
      token = request.headers['Authorization'].split(' ').last
      begin
        decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')[0]
        user_id = decoded['user_id']
        found_user = User.find_by(id: user_id)
        @current_user = found_user if found_user
      rescue JWT::DecodeError
        # do nothing => treat as guest
      end
    end

    # Check if transaction_id is provided or if we're in test mode
    restaurant = Restaurant.find(params[:restaurant_id] || 1)
    
    # Check for VIP-only restrictions
    if restaurant.vip_only_checkout?
      vip_code = params[:order][:vip_code]
      
      if vip_code.blank?
        return render json: { 
          error: "This restaurant is currently only accepting orders from VIP guests. Please enter a VIP code.",
          vip_required: true 
        }, status: :unprocessable_entity
      end
      
      # Find the VIP access code to associate with the order
      vip_access_code = VipAccessCode.find_by(restaurant_id: restaurant.id, code: vip_code)
      
      # Check if the code exists and is available
      if vip_access_code && vip_access_code.available?
        # Mark that the code was used (after validation but before saving the order)
        vip_access_code.use!
      else
        # Provide a more specific error message if the code exists but has reached its usage limit
        if vip_access_code && vip_access_code.max_uses && vip_access_code.current_uses >= vip_access_code.max_uses
          return render json: { 
            error: "This VIP code has reached its maximum usage limit.",
            vip_required: true 
          }, status: :unprocessable_entity
        else
          return render json: { 
            error: "Invalid VIP code. Please check your code and try again.",
            vip_required: true 
          }, status: :unprocessable_entity
        end
      end
    end
    
    # Initialize admin_settings if it doesn't exist
    restaurant.admin_settings ||= {}
    restaurant.admin_settings['payment_gateway'] ||= { 'test_mode' => true }
    restaurant.save if restaurant.changed?
    
    # Default to test mode if not explicitly set to false
    test_mode = restaurant.admin_settings.dig('payment_gateway', 'test_mode') != false
    
    Rails.logger.info("Restaurant: #{restaurant.id}, Test Mode: #{test_mode}")
    Rails.logger.info("Order params: #{params[:order].inspect}")
    
    # Initialize order params if not present
    params[:order] ||= {}
    
    # If we're in test mode, generate a test transaction ID
    if test_mode
      params[:order][:transaction_id] = "TEST-#{SecureRandom.hex(10)}"
      params[:order][:payment_method] = params[:order][:payment_method] || 'credit_card'
      Rails.logger.info("Generated test transaction ID: #{params[:order][:transaction_id]}")
    elsif !params[:order][:transaction_id].present?
      # If we're not in test mode and no transaction_id is provided, return an error
      return render json: { error: "Payment required before creating order" }, status: :unprocessable_entity
    end

    new_params = order_params_admin # Since create does not forcibly restrict user fields
    new_params[:restaurant_id] ||= params[:restaurant_id] || 1
    new_params[:user_id] = @current_user&.id
    
    # Set VIP access code if found
    if defined?(vip_access_code) && vip_access_code
      new_params[:vip_access_code_id] = vip_access_code.id
    end
    
    # Set payment fields
    new_params[:payment_status] = 'completed'
    new_params[:payment_amount] = new_params[:total]

    @order = Order.new(new_params)
    @order.status = 'pending'

    # Single-query for MenuItems => avoids N+1
    if @order.items.present?
      # Gather unique item IDs in the request
      item_ids = @order.items.map { |i| i[:id] }.compact.uniq

      # Load them all in one query
      menu_items_by_id = MenuItem.where(id: item_ids).index_by(&:id)
      max_required = 0

      @order.items.each do |item|
        if (menu_item = menu_items_by_id[item[:id]])
          max_required = [max_required, menu_item.advance_notice_hours].max
        end
      end

      if max_required >= 24 && @order.estimated_pickup_time.present?
        earliest_allowed = Time.current + 24.hours
        if @order.estimated_pickup_time < earliest_allowed
          return render json: {
            error: "Earliest pickup time is #{earliest_allowed.strftime('%Y-%m-%d %H:%M')}"
          }, status: :unprocessable_entity
        end
      end
    end
    
    # Validate merchandise stock levels before accepting the order
    if @order.merchandise_items.present?
      insufficient_items = []
      
      @order.merchandise_items.each do |item|
        variant = MerchandiseVariant.find_by(id: item[:merchandise_variant_id])
        if variant.nil?
          insufficient_items << { name: item[:name], reason: "variant not found" }
        elsif variant.stock_quantity < item[:quantity].to_i
          insufficient_items << { 
            name: "#{item[:name]} (#{variant.color}, #{variant.size})", 
            available: variant.stock_quantity,
            requested: item[:quantity].to_i
          }
        end
      end
      
      if insufficient_items.any?
        return render json: { 
          error: "Some items have insufficient stock",
          insufficient_items: insufficient_items
        }, status: :unprocessable_entity
      end
    end

    if @order.save
      ActiveRecord::Base.transaction do
        # Process merchandise stock adjustments
        if @order.merchandise_items.present?
          @order.merchandise_items.each do |item|
            # Find the merchandise variant
            variant = MerchandiseVariant.find_by(id: item[:merchandise_variant_id])
            
            if variant.present?
              # Adjust stock based on quantity ordered
              quantity = item[:quantity].to_i
              variant.reduce_stock!(
                quantity, 
                false, # Don't allow negative stock
                @order, # Reference to the order
                @current_user # Reference to the user who placed the order
              )
              
              # If stock is now below threshold after this order, send notification
              # But only if we're not testing
              if variant.low_stock? && !Rails.env.test? && !test_mode
                StockNotificationJob.perform_later(variant)
              end
            end
          end
        end
      end
      
      # Get notification preferences - only don't send if explicitly set to false
      notification_channels = @order.restaurant.admin_settings&.dig('notification_channels', 'orders') || {}
      
      # 1) Confirmation email - send unless explicitly disabled
      if notification_channels['email'] != false && @order.contact_email.present?
        OrderMailer.order_confirmation(@order).deliver_later
      end

      # 2) Confirmation text (async) - send unless explicitly disabled
      if notification_channels['sms'] != false && @order.contact_phone.present?
        restaurant_name = @order.restaurant.name
        # Use custom SMS sender ID if set, otherwise use restaurant name
        sms_sender = @order.restaurant.admin_settings&.dig('sms_sender_id').presence || restaurant_name
        
        # Build the item list from both regular menu items and merchandise
        item_list = @order.items.map { |i| "#{i['quantity']}x #{i['name']}" }.join(", ")
        if @order.merchandise_items.present?
          merch_list = @order.merchandise_items.map { |i| "#{i['quantity']}x #{i['name']}" }.join(", ")
          item_list += ", " + merch_list unless merch_list.blank?
        end
        
        msg = <<~TXT.squish
          Hi #{@order.contact_name.presence || 'Customer'},
          thanks for ordering from #{restaurant_name}!
          Order ##{@order.id}: #{item_list},
          total: $#{sprintf("%.2f", @order.total.to_f)}.
          We'll text you an ETA once we start preparing your order!
        TXT

        # Replace direct ClicksendClient call with a background job
        SendSmsJob.perform_later(
          to:   @order.contact_phone,
          body: msg,
          from: sms_sender
        )
      end

      render json: @order, status: :created
    else
      render json: { errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /orders/:id
  def update
    order = Order.find(params[:id])
    return render json: { error: "Forbidden" }, status: :forbidden unless can_edit?(order)

    old_status = order.status
    old_pickup_time = order.estimated_pickup_time

    # If admin => allow full params, else only allow partial
    permitted_params = if current_user&.role.in?(%w[admin super_admin])
                         order_params_admin
                       else
                         order_params_user
                       end

    if order.update(permitted_params)
      # Get notification preferences - only don't send if explicitly set to false
      notification_channels = order.restaurant.admin_settings&.dig('notification_channels', 'orders') || {}
      restaurant_name = order.restaurant.name
      # Use custom SMS sender ID if set, otherwise use restaurant name
      sms_sender = order.restaurant.admin_settings&.dig('sms_sender_id').presence || restaurant_name
      
      # If status changed from 'pending' to 'preparing'
      if old_status == 'pending' && order.status == 'preparing'
        if notification_channels['email'] != false && order.contact_email.present?
          OrderMailer.order_preparing(order).deliver_later
        end
        if notification_channels['sms'] != false && order.contact_phone.present?
          if order.requires_advance_notice?
            # For orders with 24-hour notice items
            eta_date = order.estimated_pickup_time.present? ? order.estimated_pickup_time.strftime("%A, %B %-d") : "tomorrow"
            eta_time = order.estimated_pickup_time.present? ? order.estimated_pickup_time.strftime("%-I:%M %p") : "morning"
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.id} "\
                       "is now being prepared! Your order contains items that require advance preparation. "\
                       "Pickup time: #{eta_time} TOMORROW (#{eta_date})."
          else
            # For regular orders
            eta_str = order.estimated_pickup_time.present? ? order.estimated_pickup_time.strftime("%-I:%M %p") : "soon"
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.id} "\
                       "is now being prepared! ETA: #{eta_str} TODAY."
          end

          # Send SMS asynchronously
          SendSmsJob.perform_later(
            to:   order.contact_phone,
            body: txt_body,
            from: sms_sender
          )
        end
      # If ETA was updated (and order is in preparing status)
      elsif order.status == 'preparing' && 
            old_pickup_time.present? && 
            order.estimated_pickup_time.present? && 
            old_pickup_time != order.estimated_pickup_time
        
        # Send ETA update notifications
        if notification_channels['email'] != false && order.contact_email.present?
          # Use the dedicated mailer for ETA updates
          OrderMailer.order_eta_updated(order).deliver_later
        end
        
        if notification_channels['sms'] != false && order.contact_phone.present?
          if order.requires_advance_notice?
            # For orders with 24-hour notice items
            eta_date = order.estimated_pickup_time.strftime("%A, %B %-d")
            eta_time = order.estimated_pickup_time.strftime("%-I:%M %p")
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, the pickup time for your order ##{order.id} "\
                       "has been updated. New pickup time: #{eta_time} on #{eta_date}. "\
                       "Thank you for your patience."
          else
            # For regular orders
            eta_str = order.estimated_pickup_time.strftime("%-I:%M %p")
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, the pickup time for your order ##{order.id} "\
                       "has been updated. New ETA: #{eta_str} TODAY. "\
                       "Thank you for your patience."
          end

          # Send SMS asynchronously
          SendSmsJob.perform_later(
            to:   order.contact_phone,
            body: txt_body,
            from: sms_sender
          )
        end
      end

      # If status changed to 'ready'
      if old_status != 'ready' && order.status == 'ready'
        if notification_channels['email'] != false && order.contact_email.present?
          OrderMailer.order_ready(order).deliver_later
        end
        if notification_channels['sms'] != false && order.contact_phone.present?
          msg = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.id} "\
                "is now ready for pickup! Thank you for choosing #{restaurant_name}."
          SendSmsJob.perform_later(
            to:   order.contact_phone,
            body: msg,
            from: sms_sender
          )
        end
      end

      render json: order
    else
      render json: { errors: order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /orders/:id
  def destroy
    order = Order.find(params[:id])
    return render json: { error: "Forbidden" }, status: :forbidden unless can_edit?(order)

    order.destroy
    head :no_content
  end

  private

  def can_edit?(order)
    return true if current_user&.role.in?(%w[admin super_admin])
    current_user && order.user_id == current_user.id
  end

  # For admins: allow editing everything
  def order_params_admin
    params.require(:order).permit(
      :restaurant_id,
      :user_id,
      :status,
      :total,
      :promo_code,
      :special_instructions,
      :estimated_pickup_time,
      :contact_name,
      :contact_phone,
      :contact_email,
      :payment_method,
      :transaction_id,
      :payment_status,
      :payment_amount,
      :vip_code,
      items: [
        :id,
        :name,
        :price,
        :quantity,
        :notes,
        { customizations: {} }
      ],
      merchandise_items: [
        :id,
        :merchandise_variant_id,
        :name,
        :size,
        :color,
        :price,
        :quantity,
        :image_url
      ]
    )
  end

  # For normal customers: allow only certain fields
  # e.g. let them cancel, update special_instructions, or contact info
  def order_params_user
    # If you want to let them set status to 'cancelled':
    # maybe only if old_status == 'pending'?
    params.require(:order).permit(
      :special_instructions,
      :contact_name,
      :contact_phone,
      :contact_email,
      :status
    )
  end
end
