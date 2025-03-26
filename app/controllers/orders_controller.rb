# app/controllers/orders_controller.rb

class OrdersController < ApplicationController
  before_action :authorize_request, except: [ :create, :show ]

  # Mark create, show, new_since, index, update, and destroy as public endpoints
  # that don't require restaurant context
  def public_endpoint?
    action_name.in?([
      "create", "show", "new_since", "index",
      "update", "destroy", "acknowledge", "unacknowledged"
    ])
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
    unacknowledged_orders = Order.where("created_at > ?", time_threshold)
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
    if request.headers["Authorization"].present?
      token = request.headers["Authorization"].split(" ").last
      begin
        decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: "HS256")[0]
        user_id = decoded["user_id"]
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
    restaurant.admin_settings["payment_gateway"] ||= { "test_mode" => true }
    restaurant.save if restaurant.changed?

    # Default to test mode if not explicitly set to false
    test_mode = restaurant.admin_settings.dig("payment_gateway", "test_mode") != false

    Rails.logger.info("Restaurant: #{restaurant.id}, Test Mode: #{test_mode}")
    Rails.logger.info("Order params: #{params[:order].inspect}")

    # Initialize order params if not present
    params[:order] ||= {}

    # If we're in test mode, generate a test transaction ID
    if test_mode
      params[:order][:transaction_id] = "TEST-#{SecureRandom.hex(10)}"
      params[:order][:payment_method] = params[:order][:payment_method] || "credit_card"
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
    new_params[:payment_status] = "completed"
    new_params[:payment_amount] = new_params[:total]

    @order = Order.new(new_params)
    @order.status = "pending"

    # Single-query for MenuItems => avoids N+1
    if @order.items.present?
      # Gather unique item IDs in the request
      item_ids = @order.items.map { |i| i[:id] }.compact.uniq

      # Load them all in one query
      menu_items_by_id = MenuItem.where(id: item_ids).index_by(&:id)
      max_required = 0

      @order.items.each do |item|
        if (menu_item = menu_items_by_id[item[:id]])
          max_required = [ max_required, menu_item.advance_notice_hours ].max
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
      # Log payment information for debugging
      Rails.logger.info("Order saved with payment_id: #{@order.payment_id}, transaction_id: #{@order.transaction_id}, payment_method: #{@order.payment_method}")

      # Create an OrderPayment record for the initial payment (non-staff discount orders)
      if @order.payment_method.present? && @order.payment_amount.present? && @order.payment_amount.to_f > 0
        payment_id = @order.payment_id || @order.transaction_id

        # For Stripe payments, ensure payment_id starts with 'pi_' for test mode
        if @order.payment_method == "stripe" && test_mode && (!payment_id || !payment_id.start_with?("pi_"))
          payment_id = "pi_test_#{SecureRandom.hex(16)}"
          # Update the order's payment_id as well
          @order.update(payment_id: payment_id)
          Rails.logger.info("Generated Stripe-like payment_id for test mode: #{payment_id}")
        end

        payment = @order.order_payments.create(
          payment_type: "initial",
          amount: @order.payment_amount,
          payment_method: @order.payment_method,
          status: "paid",
          transaction_id: @order.transaction_id || payment_id,
          payment_id: payment_id,
          description: "Initial payment"
        )
        Rails.logger.info("Created initial OrderPayment record: #{payment.inspect}")
      end

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

        # Process menu item stock adjustments
        if @order.items.present?
          Rails.logger.debug("Order items: #{@order.items.inspect}")

          @order.items.each do |item|
            item_id = nil
            if item.is_a?(Hash)
              item_id = item["id"] || item[:id]
            elsif item.respond_to?(:id)
              item_id = item.id
            elsif item.respond_to?(:with_indifferent_access)
              item_id = item.with_indifferent_access[:id]
            end

            Rails.logger.debug("Extracted menu item ID: #{item_id.inspect}")
            next unless item_id.present?

            menu_item = MenuItem.find_by(id: item_id)
            next unless menu_item&.enable_stock_tracking

            quantity = 0
            if item.is_a?(Hash)
              quantity = (item["quantity"] || item[:quantity] || 1).to_i
            elsif item.respond_to?(:quantity)
              quantity = item.quantity.to_i
            elsif item.respond_to?(:with_indifferent_access)
              quantity = item.with_indifferent_access[:quantity].to_i
            end

            Rails.logger.debug("Extracted quantity: #{quantity.inspect} for menu item #{menu_item.name}")

            current_stock = menu_item.stock_quantity.to_i
            new_stock = [ current_stock - quantity, 0 ].max

            menu_item.update_stock_quantity(
              new_stock,
              "order",
              "Order ##{@order.id} - #{quantity} items",
              @current_user,
              @order
            )

            if menu_item.stock_status == "low_stock" && !Rails.env.test? && !test_mode
              # TODO: implement menu item low-stock notifications if needed
            end
          end
        end
      end

      notification_channels = @order.restaurant.admin_settings&.dig("notification_channels", "orders") || {}
      restaurant_name = @order.restaurant.name

      # 1) Confirmation email (to the customer)
      if notification_channels["email"] != false && @order.contact_email.present?
        OrderMailer.order_confirmation(@order).deliver_later
      end

      # 2) Confirmation text (SMS to the customer)
      if notification_channels["sms"] == true && @order.contact_phone.present?
        sms_sender = @order.restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name

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

        SendSmsJob.perform_later(to: @order.contact_phone, body: msg, from: sms_sender)
      end

      #
      # NOTE: We have removed the additional "3) Pushover notification to
      # restaurant staff" block to avoid double notifications. The after_create
      # callback in Order (notify_pushover) already sends the Pushover alert.
      #

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

    # 1) Store original items for inventory comparison
    original_items = order.items.deep_dup

    # If admin => allow full params, else only partial
    permitted_params = if current_user&.role.in?(%w[admin super_admin])
                         order_params_admin
                       else
                         order_params_user
                       end

    if order.update(permitted_params)
      # 2) If items changed, process inventory diffs
      if permitted_params[:items].present?
        process_inventory_changes(original_items, order.items, order)
      end

      # -- Existing notification logic below --

      notification_channels = order.restaurant.admin_settings&.dig("notification_channels", "orders") || {}
      restaurant_name = order.restaurant.name
      sms_sender = order.restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name

      # If status changed from 'pending' to 'preparing'
      if old_status == "pending" && order.status == "preparing"
        if notification_channels["email"] != false && order.contact_email.present?
          OrderMailer.order_preparing(order).deliver_later
        end
        if notification_channels["sms"] == true && order.contact_phone.present?
          if order.requires_advance_notice?
            eta_date = order.estimated_pickup_time.present? ? order.estimated_pickup_time.strftime("%A, %B %-d") : "tomorrow"
            eta_time = order.estimated_pickup_time.present? ? order.estimated_pickup_time.strftime("%-I:%M %p") : "morning"
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.id} "\
                       "is now being prepared! Your order contains items that require advance preparation. "\
                       "Pickup time: #{eta_time} TOMORROW (#{eta_date})."
          else
            eta_str = order.estimated_pickup_time.present? ? order.estimated_pickup_time.strftime("%-I:%M %p") : "soon"
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.id} "\
                       "is now being prepared! ETA: #{eta_str} TODAY."
          end
          SendSmsJob.perform_later(to: order.contact_phone, body: txt_body, from: sms_sender)
        end
        
        # Send Pushover notification for order status change to preparing
        if order.restaurant.pushover_enabled?
          message = "Order ##{order.id} is now being prepared.\n\n"
          if order.estimated_pickup_time.present?
            if order.requires_advance_notice?
              eta_date = order.estimated_pickup_time.strftime("%A, %B %-d")
              eta_time = order.estimated_pickup_time.strftime("%-I:%M %p")
              message += "Pickup time: #{eta_time} on #{eta_date}"
            else
              eta_str = order.estimated_pickup_time.strftime("%-I:%M %p")
              message += "ETA: #{eta_str} TODAY"
            end
          end
          
          order.restaurant.send_pushover_notification(
            message,
            "Order Status Update",
            { priority: 0, sound: "pushover" }
          )
        end

      # If ETA was updated (and order is in preparing status)
      elsif order.status == "preparing" &&
            old_pickup_time.present? &&
            order.estimated_pickup_time.present? &&
            old_pickup_time != order.estimated_pickup_time

        if notification_channels["email"] != false && order.contact_email.present?
          OrderMailer.order_eta_updated(order).deliver_later
        end
        if notification_channels["sms"] == true && order.contact_phone.present?
          if order.requires_advance_notice?
            eta_date = order.estimated_pickup_time.strftime("%A, %B %-d")
            eta_time = order.estimated_pickup_time.strftime("%-I:%M %p")
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, the pickup time for your order ##{order.id} "\
                       "has been updated. New pickup time: #{eta_time} on #{eta_date}. "\
                       "Thank you for your patience."
          else
            eta_str = order.estimated_pickup_time.strftime("%-I:%M %p")
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, the pickup time for your order ##{order.id} "\
                       "has been updated. New ETA: #{eta_str} TODAY. "\
                       "Thank you for your patience."
          end
          SendSmsJob.perform_later(to: order.contact_phone, body: txt_body, from: sms_sender)
        end
        
        # Send Pushover notification for ETA update
        if order.restaurant.pushover_enabled?
          message = "Order ##{order.id} pickup time updated.\n\n"
          if order.requires_advance_notice?
            eta_date = order.estimated_pickup_time.strftime("%A, %B %-d")
            eta_time = order.estimated_pickup_time.strftime("%-I:%M %p")
            message += "New pickup time: #{eta_time} on #{eta_date}"
          else
            eta_str = order.estimated_pickup_time.strftime("%-I:%M %p")
            message += "New ETA: #{eta_str} TODAY"
          end
          
          message += "\nCustomer: #{order.contact_name}" if order.contact_name.present?
          
          order.restaurant.send_pushover_notification(
            message,
            "Order ETA Updated",
            { priority: 0, sound: "pushover" }
          )
        end
      end

      # If status changed to 'ready'
      if old_status != "ready" && order.status == "ready"
        if notification_channels["email"] != false && order.contact_email.present?
          OrderMailer.order_ready(order).deliver_later
        end
        if notification_channels["sms"] == true && order.contact_phone.present?
          msg = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.id} "\
                "is now ready for pickup! Thank you for choosing #{restaurant_name}."
          SendSmsJob.perform_later(to: order.contact_phone, body: msg, from: sms_sender)
        end
        
        # Send Pushover notification for order ready status
        if order.restaurant.pushover_enabled?
          message = "Order ##{order.id} is now ready for pickup!\n\n"
          message += "Customer: #{order.contact_name}\n" if order.contact_name.present?
          message += "Phone: #{order.contact_phone}" if order.contact_phone.present?
          
          order.restaurant.send_pushover_notification(
            message,
            "Order Ready for Pickup",
            { 
              priority: 1,  # High priority to bypass quiet hours
              sound: "siren"  # Attention-grabbing sound for ready orders
            }
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

  # For admins: allow editing everything with custom handling for customizations
  def order_params_admin
    # First permit the items parameter at the top level to avoid "unpermitted parameter: :items" error
    params.require(:order).permit![:items] if params[:order][:items].present?
    
    # Then get all the standard permitted parameters
    sanitized = params.require(:order).permit(
      :id,
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
      :items, # Permit items as a whole first
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
    
    # Then handle items with customizations separately
    if params[:order][:items].present?
      sanitized[:items] = params[:order][:items].map do |item|
        item_params = {}
        
        # Copy permitted scalar values
        [:id, :name, :price, :quantity, :notes, :enable_stock_tracking, 
         :stock_quantity, :damaged_quantity, :low_stock_threshold].each do |key|
          item_params[key] = item[key] if item.key?(key)
        end
        
        # Copy customizations as-is
        item_params[:customizations] = item[:customizations] if item[:customizations].present?
        
        # Copy array-style customizations if present
        if item[:customizations].is_a?(Array)
          item_params[:customizations] = item[:customizations].map do |c|
            c.permit(:option_id, :option_name, :option_group_id, :option_group_name, :price)
          end
        end
        
        item_params
      end
    end
    
    sanitized
  end

  # For normal customers: allow only certain fields
  def order_params_user
    params.require(:order).permit(
      :special_instructions,
      :contact_name,
      :contact_phone,
      :contact_email,
      :status
    )
  end

  # ----------------------------------------------------
  # The key new method: process_inventory_changes
  # ----------------------------------------------------
  def process_inventory_changes(original_items, new_items, order)
    # Calculate totals by menu item ID to properly handle duplicates
    original_totals = {}
    original_items.each do |item|
      item_id = extract_item_id(item).to_s
      quantity = extract_quantity(item)
      original_totals[item_id] ||= 0
      original_totals[item_id] += quantity
    end

    new_totals = {}
    tracked_items = {}  # To keep track of inventory-tracked items

    new_items.each do |item|
      item_id = extract_item_id(item).to_s
      quantity = extract_quantity(item)
      new_totals[item_id] ||= 0
      new_totals[item_id] += quantity

      # Store reference to first item with this ID for enable_stock_tracking check
      tracked_items[item_id] ||= item
    end

    Rails.logger.debug("Original totals: #{original_totals}")
    Rails.logger.debug("New totals: #{new_totals}")

    # Process inventory adjustments for each unique menu item ID
    (original_totals.keys | new_totals.keys).uniq.each do |item_id|
      menu_item = MenuItem.find_by(id: item_id)
      next unless menu_item&.enable_stock_tracking

      original_qty = original_totals[item_id] || 0
      new_qty = new_totals[item_id] || 0
      qty_diff = new_qty - original_qty

      # Skip if no change in quantity
      next if qty_diff == 0

      # If item is new to the order (wasn't in original)
      if original_qty == 0
        process_new_item(menu_item, new_qty, order)
      # If item was removed from the order
      elsif new_qty == 0
        process_removed_item(menu_item, original_qty, order)
      # If quantity changed
      else
        process_quantity_change(menu_item, original_qty, new_qty, qty_diff, order)
      end
    end
  end

  # Helper methods for inventory processing

  def extract_item_id(item)
    if item.is_a?(Hash)
      item[:id] || item["id"]
    elsif item.respond_to?(:id)
      item.id
    elsif item.respond_to?(:with_indifferent_access)
      item.with_indifferent_access[:id]
    end
  end

  def extract_quantity(item)
    quantity = 1 # Default
    if item.is_a?(Hash)
      quantity = (item[:quantity] || item["quantity"] || 1).to_i
    elsif item.respond_to?(:quantity)
      quantity = item.quantity.to_i
    elsif item.respond_to?(:with_indifferent_access)
      quantity = item.with_indifferent_access[:quantity].to_i
    end
    quantity
  end

  def process_new_item(menu_item, quantity, order)
    current_stock = menu_item.stock_quantity.to_i
    new_stock = [ current_stock - quantity, 0 ].max

    menu_item.update_stock_quantity(
      new_stock,
      "order",
      "Order ##{order.id} - Added item during edit (qty #{quantity})",
      @current_user,
      order
    )
  end

  def process_removed_item(menu_item, quantity, order)
    # Only add back 1 at a time for removed items to prevent double-counting
    # since the frontend InventoryReversionDialog may have already handled some
    current_stock = menu_item.stock_quantity.to_i

    # Get the count of this item that was in the previous order
    removed_qty = quantity

    # Add debug logging
    Rails.logger.debug("Returning item to inventory: #{menu_item.name}, quantity: #{removed_qty}, current stock: #{current_stock}")

    new_stock = current_stock + removed_qty

    menu_item.update_stock_quantity(
      new_stock,
      "adjustment",
      "Order ##{order.id} - Removed item during edit (qty #{removed_qty})",
      @current_user,
      order
    )
  end

  def process_quantity_change(menu_item, original_qty, new_qty, qty_diff, order)
    current_stock = menu_item.stock_quantity.to_i
    new_stock = current_stock - qty_diff

    menu_item.update_stock_quantity(
      [ new_stock, 0 ].max,
      "adjustment",
      "Order ##{order.id} - Quantity changed from #{original_qty} to #{new_qty}",
      @current_user,
      order
    )
  end
end
