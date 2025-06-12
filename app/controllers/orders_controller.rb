# app/controllers/orders_controller.rb

class OrdersController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request, except: [ :create, :show ]
  before_action :ensure_tenant_context

  # GET /orders
  def index
    # Use Pundit's policy_scope to filter orders based on user role
    # This automatically handles staff/admin/customer authorization
    @orders = policy_scope(Order)

    # Enhanced filtering logic consolidated from staff_orders method
    
    # Filter for online orders only (customer orders)
    if params[:online_orders_only].present? && params[:online_orders_only] == 'true'
      @orders = @orders.where(staff_created: false, is_staff_order: false)
    end

    # Filter by staff member if provided
    if params[:staff_member_id].present?
      # Handle both user ID (admin/super_admin) or staff member ID formats
      if params[:staff_member_id].to_s.include?('user_')
        # Extract user ID from 'user_123' format
        user_id = params[:staff_member_id].to_s.gsub('user_', '')
        @orders = @orders.where(created_by_user_id: user_id)
      else
        # This is a staff member ID
        @orders = @orders.where(created_by_staff_id: params[:staff_member_id])
      end
    end

    # Filter by user_id if provided (for admin-created orders)
    if params[:user_id].present?
      user_orders = @orders.where(created_by_user_id: params[:user_id])
      
      # Include online orders if requested
      if params[:include_online_orders].present? && params[:include_online_orders] == 'true'
        online_orders = @orders.where(staff_created: false, is_staff_order: false)
        @orders = user_orders.or(online_orders)
      else
        @orders = user_orders
      end
    end

    # Filter by restaurant_id if provided
    if params[:restaurant_id].present?
      @orders = @orders.where(restaurant_id: params[:restaurant_id])
    end

    # Filter by status if provided
    if params[:status].present?
      @orders = @orders.where(status: params[:status])
    end

    # Filter by location_id if provided (support both locationId and location_id)
    location_id = params[:location_id] || params[:locationId]
    if location_id.present?
      @orders = @orders.where(location_id: location_id)
      Rails.logger.info("[LOCATION FILTER] Filtering orders by location_id: #{location_id}")
      Rails.logger.info("[LOCATION FILTER] Orders count after location filter: #{@orders.count}")
    end

    # Enhanced date filtering with timezone handling (from staff_orders)
    if params[:date_from].present? && params[:date_to].present?
      begin
        # Debug log for incoming date parameters
        Rails.logger.info("[DATE FILTER DEBUG] Received date parameters:")
        Rails.logger.info("[DATE FILTER DEBUG] date_from: #{params[:date_from]}")
        Rails.logger.info("[DATE FILTER DEBUG] date_to: #{params[:date_to]}")
        Rails.logger.info("[DATE FILTER DEBUG] Current time in Rails: #{Time.zone.now}")
        
        # Parse the dates with timezone information preserved
        date_from_str = params[:date_from]
        date_to_str = params[:date_to]
        
        # Parse the dates - Time.zone.parse will handle the timezone conversion
        date_from = Time.zone.parse(date_from_str)
        date_to = Time.zone.parse(date_to_str)
        
        # For dates in UTC (ending with Z), adjust for timezone
        if date_from_str.end_with?('Z') || date_to_str.end_with?('Z')
          Rails.logger.info("[DATE FILTER DEBUG] Detected UTC dates, adjusting for timezone")
          date_from = date_from.beginning_of_day
          date_to = date_to.end_of_day
        end
        
        # Debug log for parsed dates
        Rails.logger.info("[DATE FILTER DEBUG] Parsed dates:")
        Rails.logger.info("[DATE FILTER DEBUG] date_from parsed: #{date_from}")
        Rails.logger.info("[DATE FILTER DEBUG] date_to parsed: #{date_to}")
        
        # Extend the range slightly to ensure we capture all orders
        date_from = date_from - 1.second
        date_to = date_to + 1.second
        
        # Apply date filter
        orders_before_filter = @orders.count
        @orders = @orders.where(created_at: date_from..date_to)
        orders_after_filter = @orders.count
        
        Rails.logger.info("[DATE FILTER DEBUG] Orders count before filter: #{orders_before_filter}")
        Rails.logger.info("[DATE FILTER DEBUG] Orders count after filter: #{orders_after_filter}")
        
      rescue => e
        # Log the error but continue with unfiltered orders
        Rails.logger.error("Error parsing date range: #{e.message}")
        Rails.logger.error("date_from: #{params[:date_from]}, date_to: #{params[:date_to]}")
      end
    end

    # Search functionality
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      
      # Search in basic order fields
      basic_search = @orders.where(
        "id::text ILIKE ? OR contact_name ILIKE ? OR contact_email ILIKE ? OR contact_phone ILIKE ? OR special_instructions ILIKE ?",
        search_term, search_term, search_term, search_term, search_term
      )
      
      # Search in order items using JSON operators and apply the same filters
      # Since items are stored as JSON, we search within the JSON array
      item_search = @orders.where(
        "EXISTS (
          SELECT 1 FROM jsonb_array_elements(items) as item
          WHERE item->>'name' ILIKE ? OR item->>'notes' ILIKE ?
        )", search_term, search_term
      )
      
      # Combine both search results while maintaining all filters
      @orders = basic_search.or(item_search)
    end

    # Get total count after filtering but before pagination
    total_count = @orders.count

    # Add pagination
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 10).to_i

    # Apply sorting
    sort_by = params[:sort_by] || 'created_at'
    sort_direction = params[:sort_direction] || 'desc'
    
    # Validate sort parameters to prevent SQL injection
    valid_sort_columns = ['id', 'created_at', 'updated_at', 'status', 'total']
    valid_sort_directions = ['asc', 'desc']
    
    sort_by = 'created_at' unless valid_sort_columns.include?(sort_by)
    sort_direction = 'desc' unless valid_sort_directions.include?(sort_direction)
    
    # Include location association to ensure location data is available in the response
    @orders = @orders.includes(:location)
                     .order("#{sort_by} #{sort_direction}")
                     .offset((page - 1) * per_page)
                     .limit(per_page)

    # Calculate total pages
    total_pages = (total_count.to_f / per_page).ceil

    # Include location data in the response
    orders_with_location = @orders.as_json(include: :location)

    render json: {
      orders: orders_with_location,
      total_count: total_count,
      page: page,
      per_page: per_page,
      total_pages: total_pages
    }, status: :ok

  end

  # GET /orders/:id
  def show
    order = Order.find(params[:id])
    authorize order
    render json: order
  end

  # GET /orders/new_since/:id
  def new_since
    # Only allow staff or above to access this endpoint
    authorize Order, :index?
    
    last_id = params[:id].to_i
    # Apply policy scope to ensure proper filtering based on role
    new_orders = policy_scope(Order).where("id > ?", last_id)
                      .where(staff_created: [false, nil]) # Exclude staff-created orders
                      .order(:id)
    render json: new_orders, status: :ok
  end



  # GET /orders/creators
  # Returns a list of users who have created orders (staff, admin, super_admin) for the current restaurant only
  def order_creators
    # Only allow admin or above to access this endpoint
    unless current_user&.admin_or_above?
      return render json: { error: "Forbidden" }, status: :forbidden
    end
    
    # Find all users who have created orders for the current restaurant
    # Get unique user_ids from orders where created_by_user_id is not null and restaurant_id matches current restaurant
    user_ids = Order.where(restaurant_id: current_restaurant.id)
                   .where.not(created_by_user_id: nil)
                   .distinct
                   .pluck(:created_by_user_id)
    
    # Get users with those IDs who are staff or admin by default
    # Only include users who belong to the current restaurant
    @users = User.where(id: user_ids)
                .where(role: ['staff', 'admin'])
                .where(restaurant_id: current_restaurant.id)
    
    # Format the response
    creators = @users.map do |user|
      {
        id: "user_#{user.id}",
        name: "#{user.first_name} #{user.last_name}",
        type: 'user',
        role: user.role
      }
    end
    
    # Log the response for debugging
    Rails.logger.info("[TENANT ISOLATION] Returning #{creators.length} order creators for restaurant #{current_restaurant.id}")
    Rails.logger.info("[TENANT ISOLATION] Current user role: #{current_user.role}, restaurant_id: #{current_user.restaurant_id}")
    Rails.logger.info("[TENANT ISOLATION] Current restaurant: #{current_restaurant.id}")
    
    # Return only users who have created orders for this restaurant
    render json: creators
  end

  # GET /orders/unacknowledged
  def unacknowledged
    unless current_user&.role.in?(%w[admin super_admin staff])
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    # Get time threshold (default to 24 hours ago)
    hours = params[:hours].present? ? params[:hours].to_i : 24
    time_threshold = Time.current - hours.hours

    # Check if this user has any previous acknowledgments
    has_previous_acknowledgments = OrderAcknowledgment.exists?(user_id: current_user.id)

    # Build the query based on whether this is a first-time user
    if has_previous_acknowledgments
      # Regular case: Return orders not acknowledged by this specific user
      unacknowledged_orders = Order.where("created_at > ?", time_threshold)
                                   .where.not(id: current_user.acknowledged_orders.pluck(:id))
                                   .where(staff_created: [false, nil]) # Exclude staff-created orders
                                   .order(created_at: :desc)
    else
      # First-time user case: Only return orders that haven't been acknowledged by anyone
      # OR orders that came in after the last global acknowledgment
      unacknowledged_orders = Order.where("created_at > ?", time_threshold)
                                   .where(staff_created: [false, nil]) # Exclude staff-created orders
                                   .where("global_last_acknowledged_at IS NULL OR created_at > global_last_acknowledged_at")
                                   .order(created_at: :desc)
    end

    render json: unacknowledged_orders, status: :ok
  end

  # POST /orders/:id/acknowledge
  def acknowledge
    order = Order.find(params[:id])
    
    # Use Pundit to authorize the action
    authorize order, :acknowledge?

    # Create acknowledgment record
    acknowledgment = OrderAcknowledgment.find_or_initialize_by(
      order: order,
      user: current_user
    )

    if acknowledgment.new_record? && acknowledgment.save
      # Update the global_last_acknowledged_at timestamp
      order.update(global_last_acknowledged_at: Time.current)
      
      # Broadcast the order update via WebSockets
      WebsocketBroadcastService.broadcast_order_update(order)
      
      render json: { message: "Order #{order.order_number.presence || order.id} acknowledged" }, status: :ok
    else
      render json: { error: "Failed to acknowledge order" }, status: :unprocessable_entity
    end
  end

  # POST /orders
  #
  # Creates a new order with the following behavior:
  # - Validates payment information
  # - Checks VIP mode restrictions (bypassed for admin/staff users)
  # - Processes inventory adjustments
  # - Sends notifications to customers
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
      # Skip VIP validation for admin/staff users
      # This allows staff to create orders through StaffOrderModal even when VIP mode is enabled
      is_admin_user = @current_user && @current_user.role.in?(%w[admin super_admin])
      
      # Log the VIP mode bypass for debugging
      Rails.logger.info("VIP Mode Check - User: #{@current_user&.id}, Is Admin: #{is_admin_user}, Restaurant: #{restaurant.id}")
      
      # Only enforce VIP code for non-admin users
      if !is_admin_user
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

    # Get permitted parameters through strong parameters
    new_params = order_params_admin
    
    # Set essential attributes that might not be in the params
    new_params[:restaurant_id] ||= params[:restaurant_id] || 1
    new_params[:user_id] = @current_user&.id
    new_params[:created_by_user_id] = @current_user&.id if @current_user
    
    # Use OrderService to handle location_id assignment
    # This will automatically use the default location if none is provided
    order_service = OrderService.new(current_restaurant)
    
    # We'll let the OrderService handle the location assignment during creation
    
    # Set payment status and amount
    new_params[:payment_status] = "completed"
    new_params[:payment_amount] = new_params[:total]
    
    # Set VIP access code if found
    if defined?(vip_access_code) && vip_access_code
      new_params[:vip_access_code_id] = vip_access_code.id
    end
    
    # Handle staff-specific logic if needed
    if new_params[:is_staff_order] == true
      # IMPORTANT: Always use the pre_discount_total from the frontend parameters
      # Only fall back to total if pre_discount_total is not provided
      if new_params[:pre_discount_total].present?
        Rails.logger.info("Using pre_discount_total from frontend: #{new_params[:pre_discount_total]}")
      elsif new_params[:total].present?
        Rails.logger.info("No pre_discount_total provided, using total: #{new_params[:total]}")
        new_params[:pre_discount_total] = new_params[:total]
      end
      
      # If no created_by_staff_id was provided but the user has a staff record, use that
      if new_params[:created_by_staff_id].blank? && @current_user&.staff_member.present?
        new_params[:created_by_staff_id] = @current_user.staff_member.id
        Rails.logger.info("Fallback: Setting created_by_staff_id to #{@current_user.staff_member.id} for user #{@current_user.id}")
      end
    end

    # Create the order using OrderService for proper tenant isolation
    @order = order_service.create_order(new_params)
    @order.status = "pending"
    # The staff_created flag will be set automatically by the before_create callback
    # based on the staff_modal virtual attribute

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

    # Validate that all selected options are available
    if @order.items.present?
      unavailable_options = []
      items_with_unavailable_required_groups = []

      @order.items.each do |item|
        # Check if the menu item has required groups with all options unavailable
        menu_item = menu_items_by_id[item[:id]]
        if menu_item && menu_item.has_required_groups_with_unavailable_options?
          # Get the names of the problematic option groups
          unavailable_groups = menu_item.required_groups_with_unavailable_options.map(&:name)
          
          items_with_unavailable_required_groups << {
            item_name: menu_item.name,
            item_id: menu_item.id,
            unavailable_groups: unavailable_groups
          }
          next # Skip further validation for this item
        end
        
        # Skip items without selected options
        next unless item[:selected_options].is_a?(Array) && item[:selected_options].any?

        # Get all option IDs from the item
        option_ids = item[:selected_options].map { |opt| opt[:id] }.compact
        
        # Skip if no valid option IDs
        next if option_ids.empty?
        
        # Find any unavailable options
        unavailable = Option.where(id: option_ids, is_available: false)
        
        if unavailable.any?
          menu_item = menu_items_by_id[item[:id]]
          item_name = menu_item ? menu_item.name : "Unknown item"
          
          unavailable.each do |option|
            unavailable_options << {
              item_name: item_name,
              option_name: option.name,
              option_id: option.id
            }
          end
        end
      end

      # Check for items with unavailable required groups first
      if items_with_unavailable_required_groups.any?
        return render json: {
          error: "Some items have required option groups with no available options",
          items_with_unavailable_required_groups: items_with_unavailable_required_groups
        }, status: :unprocessable_entity
      end
      
      # Then check for individual unavailable options
      if unavailable_options.any?
        return render json: {
          error: "Some selected options are currently unavailable",
          unavailable_options: unavailable_options
        }, status: :unprocessable_entity
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
      # Broadcast the new order via WebSockets
      WebsocketBroadcastService.broadcast_new_order(@order)
      
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

        # Format payment details to ensure proper display in UI
        payment_details = @order.payment_details || params[:order][:payment_details]
        
        # Format staff order params if present
        if payment_details && payment_details['staffOrderParams'].present?
          staff_params = payment_details['staffOrderParams']
          
          # Convert staff params to string representation
          # Use the order's actual is_staff_order value to ensure consistency
          formatted_staff_params = {
            'is_staff_order' => @order.is_staff_order ? 'true' : 'false',
            'staff_member_id' => @order.staff_member_id.to_s,
            'staff_on_duty' => @order.staff_on_duty ? 'true' : 'false',
            'discount_type' => staff_params['discount_type'].to_s,
            'no_discount' => staff_params['no_discount'].to_s,
            'use_house_account' => @order.use_house_account ? 'true' : 'false',
            'created_by_staff_id' => @order.created_by_staff_id.to_s,
            'pre_discount_total' => @order.pre_discount_total.to_s
          }
          
          # Replace the object with the formatted version
          payment_details['staffOrderParams'] = formatted_staff_params
        # If staffOrderParams is not present but this is a staff order, add it
        elsif @order.is_staff_order
          payment_details ||= {}
          
          # Get the original pre_discount_total from different possible locations
          original_pre_discount_total = if params.dig(:order, :pre_discount_total).present?
            params.dig(:order, :pre_discount_total)
          elsif params.dig(:order, :payment_details, :staffOrderParams, :pre_discount_total).present?
            params.dig(:order, :payment_details, :staffOrderParams, :pre_discount_total)
          else
            nil
          end
          
          # Always use the original pre_discount_total from params if available
          # This is critical for staff orders to ensure correct discount calculation
          pre_discount_value = if original_pre_discount_total.present?
            original_pre_discount_total.to_s
          else
            # If no original value is available, use the order's current pre_discount_total
            # This is a fallback and should be avoided if possible
            @order.pre_discount_total.to_s
          end
          
          # Log the values for debugging
          Rails.logger.info("OrderPayment staffOrderParams: Using pre_discount_total #{pre_discount_value} (from params: #{original_pre_discount_total}, from order: #{@order.pre_discount_total})")
          
          # Get discount_type from original parameters if available
          original_discount_type = if params.dig(:order, :discount_type).present?
            params.dig(:order, :discount_type)
          elsif params.dig(:order, :payment_details, :staffOrderParams, :discount_type).present?
            params.dig(:order, :payment_details, :staffOrderParams, :discount_type)
          else
            # Fallback: infer from staff_on_duty for backward compatibility
            @order.staff_on_duty ? 'on_duty' : 'off_duty'
          end
          
          # Get no_discount flag from original parameters if available
          original_no_discount = if params.dig(:order, :no_discount).present?
            params.dig(:order, :no_discount)
          elsif params.dig(:order, :payment_details, :staffOrderParams, :no_discount).present?
            params.dig(:order, :payment_details, :staffOrderParams, :no_discount)
          else
            'false'
          end
          
          payment_details['staffOrderParams'] = {
            'is_staff_order' => 'true',
            'staff_member_id' => @order.staff_member_id.to_s,
            'staff_on_duty' => @order.staff_on_duty ? 'true' : 'false',
            'discount_type' => original_discount_type.to_s,
            'no_discount' => original_no_discount.to_s,
            'use_house_account' => @order.use_house_account ? 'true' : 'false',
            'created_by_staff_id' => @order.created_by_staff_id.to_s,
            'pre_discount_total' => pre_discount_value
          }
        end
        
        payment = @order.order_payments.create(
          payment_type: "initial",
          amount: @order.payment_amount,
          payment_method: @order.payment_method,
          status: "paid",
          transaction_id: @order.transaction_id || payment_id,
          payment_id: payment_id,
          description: "Initial payment",
          payment_details: payment_details
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
              "Order ##{@order.order_number.presence || @order.id} - #{quantity} items",
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
          Order ##{@order.order_number.presence || @order.id}: #{item_list},
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
    # Find the order first
    order = Order.find(params[:id])
    # Store the original order status for comparison
    original_status = order&.status
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
    
    # IMPORTANT: Don't allow frontend to set or override refund status
    # This prevents inconsistencies between payment_status and status
    if permitted_params[:status].present? && 
       (['refunded'].include?(permitted_params[:status]) || 
        ['refunded'].include?(order.status))
      # Remove status from permitted params to preserve the server-calculated refund status
      # or prevent the frontend from setting a refund status
      Rails.logger.info("Preventing frontend refund status change: #{permitted_params[:status]} -> #{order.status}")
      permitted_params.delete(:status)
    end

    if order.update(permitted_params)
      # Broadcast the order update via WebSockets
      WebsocketBroadcastService.broadcast_order_update(order)
      
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
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.order_number.presence || order.id} "\
                       "is now being prepared! Your order contains items that require advance preparation. "\
                       "Pickup time: #{eta_time} TOMORROW (#{eta_date})."
          else
            eta_str = order.estimated_pickup_time.present? ? order.estimated_pickup_time.strftime("%-I:%M %p") : "soon"
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.order_number.presence || order.id} "\
                       "is now being prepared! ETA: #{eta_str} TODAY."
          end
          SendSmsJob.perform_later(to: order.contact_phone, body: txt_body, from: sms_sender)
        end
        
        # Send Pushover notification for order status change to preparing
        if order.restaurant.pushover_enabled?
          message = "Order ##{order.order_number.presence || order.id} is now being prepared.\n\n"
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
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, the pickup time for your order ##{order.order_number.presence || order.id} "\
                       "has been updated. New pickup time: #{eta_time} on #{eta_date}. "\
                       "Thank you for your patience."
          else
            eta_str = order.estimated_pickup_time.strftime("%-I:%M %p")
            txt_body = "Hi #{order.contact_name.presence || 'Customer'}, the pickup time for your order ##{order.order_number.presence || order.id} "\
                       "has been updated. New ETA: #{eta_str} TODAY. "\
                       "Thank you for your patience."
          end
          SendSmsJob.perform_later(to: order.contact_phone, body: txt_body, from: sms_sender)
        end
        
        # Send Pushover notification for ETA update
        if order.restaurant.pushover_enabled?
          message = "Order ##{order.order_number.presence || order.id} pickup time updated.\n\n"
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
          msg = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.order_number.presence || order.id} "\
                "is now ready for pickup! Thank you for choosing #{restaurant_name}."
          SendSmsJob.perform_later(to: order.contact_phone, body: msg, from: sms_sender)
        end
        
        # Send Pushover notification for order ready status
        if order.restaurant.pushover_enabled?
          message = "Order ##{order.order_number.presence || order.id} is now ready for pickup!\n\n"
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
    # Allow admin, super_admin, and staff users to edit any order
    return true if current_user&.role.in?(%w[admin super_admin staff])
    # For customers, only allow editing their own orders
    current_user && order.user_id == current_user.id
  end

  # For admins: allow editing everything with proper handling for nested attributes
  def order_params_admin
    # Use Rails' strong parameters with proper nesting
    permitted_params = params.require(:order).permit(
      :id, :restaurant_id, :user_id, :status, :total, :subtotal, :tax, 
      :tip, :service_fee, :transaction_id, :payment_id, :payment_method, 
      :payment_status, :payment_amount, :contact_name, :contact_email, 
      :contact_phone, :special_instructions, :estimated_pickup_time, 
      :pickup_time, :is_staff_order, :staff_member_id, :staff_on_duty, 
      :use_house_account, :created_by_staff_id, :created_by_user_id, 
      :pre_discount_total, :vip_code, :vip_access_code_id, :staff_modal, :location_id,
      # Handle nested attributes properly
      items: [:id, :name, :price, :quantity, :notes, :menu_id, :category_id, { customizations: {} }],
      merchandise_items: [:id, :name, :price, :quantity, :merchandise_variant_id, :notes],
      # Allow all payment details attributes to be passed through
      payment_details: {})
    
    # Convert payment_details to a hash if it's present
    if permitted_params[:payment_details].present?
      # Ensure payment_details is a hash
      permitted_params[:payment_details] = permitted_params[:payment_details].to_h
    end
    
    # Log what we're doing for debugging
    Rails.logger.info("Using strong parameters for order with staff_modal=#{permitted_params[:staff_modal]}")
    
    # Return the permitted parameters
    permitted_params
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
      "Order ##{order.order_number.presence || order.id} - Added item during edit (qty #{quantity})",
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
      "Order ##{order.order_number.presence || order.id} - Removed item during edit (qty #{removed_qty})",
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
      "Order ##{order.order_number.presence || order.id} - Quantity changed from #{original_qty} to #{new_qty}",
      @current_user,
      order
    )
  end
end
