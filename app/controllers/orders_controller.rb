# app/controllers/orders_controller.rb

class OrdersController < ApplicationController
  include TenantIsolation

  before_action :authorize_request, except: [ :create, :show, :by_transaction ]
  before_action :ensure_tenant_context

  # GET /orders
  def index
    # Use Pundit's policy_scope to filter orders based on user role
    # This automatically handles staff/admin/customer authorization
    @orders = policy_scope(Order)

    # Enhanced filtering logic consolidated from staff_orders method

    # Filter for online orders only (customer orders)
    if params[:online_orders_only].present? && params[:online_orders_only] == "true"
      @orders = @orders.where(staff_created: false, is_staff_order: false)
    end

    # Filter by staff member if provided
    if params[:staff_member_id].present?
      # Handle both user ID (admin/super_admin) or staff member ID formats
      if params[:staff_member_id].to_s.include?("user_")
        # Extract user ID from 'user_123' format
        user_id = params[:staff_member_id].to_s.gsub("user_", "")
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
      if params[:include_online_orders].present? && params[:include_online_orders] == "true"
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

        # Parse the dates with the incoming timezone preserved. The frontend already
        # sends exact UTC boundaries for the selected local date range, so we should
        # not coerce them back to the server's beginning/end_of_day.
        date_from = Time.zone.parse(date_from_str)
        date_to = Time.zone.parse(date_to_str)

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

      # Performance optimization: Use different strategies based on search pattern
      search_queries = []

      # 1. Order number search with multiple strategies for better UX
      if params[:search].present?
        raw_search = params[:search].strip

        # Strategy 1: Exact order number match (fastest)
        search_queries << @orders.where("order_number = ?", raw_search)

        # Strategy 2: Partial order number match (for "HAF-O-123" format)
        search_queries << @orders.where("order_number ILIKE ?", search_term)

        # Strategy 3: Handle numeric-only searches (e.g., "123" should match "HAF-O-123")
        if raw_search.match?(/^\d+$/)
          # For numeric searches, look for the number part after the last dash
          numeric_pattern = "%-#{raw_search}"
          search_queries << @orders.where("order_number ILIKE ?", numeric_pattern)

          # Also try with leading zeros (e.g., "1" matches "HAF-O-001")
          if raw_search.length <= 3
            padded_number = raw_search.rjust(3, "0")
            padded_pattern = "%-#{padded_number}"
            search_queries << @orders.where("order_number ILIKE ?", padded_pattern)
          end
        end

        # Strategy 4: Handle partial prefix searches (e.g., "HAF" matches "HAF-O-123")
        if raw_search.match?(/^[A-Za-z]+$/) && raw_search.length >= 2
          prefix_pattern = "#{raw_search}%"
          search_queries << @orders.where("order_number ILIKE ?", prefix_pattern)
        end
      end

      # 2. Basic order fields search (existing functionality)
      basic_search = @orders.where(
        "id::text ILIKE ? OR contact_name ILIKE ? OR contact_email ILIKE ? OR contact_phone ILIKE ? OR special_instructions ILIKE ?",
        search_term, search_term, search_term, search_term, search_term
      )
      search_queries << basic_search

      # 3. Order items search using JSON operators (existing functionality)
      item_search = @orders.where(
        "EXISTS (
          SELECT 1 FROM jsonb_array_elements(items) as item
          WHERE item->>'name' ILIKE ? OR item->>'notes' ILIKE ?
        )", search_term, search_term
      )
      search_queries << item_search

      # Combine all search results using UNION for better performance
      # This is more efficient than multiple OR conditions
      if search_queries.length > 1
        combined_query = search_queries.first
        search_queries[1..-1].each do |query|
          combined_query = combined_query.or(query)
        end
        @orders = combined_query.distinct
      else
        @orders = search_queries.first || @orders.none
      end
    end

    # Get total count after filtering but before pagination
    total_count = @orders.count

    # Add pagination
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 10).to_i

    # Apply sorting
    sort_by = params[:sort_by] || "created_at"
    sort_direction = params[:sort_direction] || "desc"

    # Validate sort parameters to prevent SQL injection
    valid_sort_columns = [ "id", "created_at", "updated_at", "status", "total" ]
    valid_sort_directions = [ "asc", "desc" ]

    sort_by = "created_at" unless valid_sort_columns.include?(sort_by)
    sort_direction = "desc" unless valid_sort_directions.include?(sort_direction)

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

  # POST /orders/by_transaction
  def by_transaction
    transaction_id = params[:transaction_id].presence || params[:payment_intent_id].presence
    unless transaction_id.present?
      return render json: { error: "transaction_id is required" }, status: :bad_request
    end

    client_secret = params[:payment_intent_client_secret].presence || params[:client_secret].presence
    unless valid_transaction_lookup_secret?(transaction_id, client_secret)
      return render json: { error: "Valid payment intent client secret is required" }, status: :forbidden
    end

    order = Order.where(restaurant_id: current_restaurant.id, transaction_id: transaction_id)
                 .where.not(payment_status: [ "canceled", "refunded" ])
                 .first

    if order.present?
      render json: public_order_confirmation_json(order), status: :ok
    else
      head :not_found
    end
  end

  # GET /orders/new_since/:id
  def new_since
    # Only allow staff or above to access this endpoint
    authorize Order, :index?

    last_id = params[:id].to_i
    # Apply policy scope to ensure proper filtering based on role
    new_orders = policy_scope(Order).where("id > ?", last_id)
                      .where(staff_created: [ false, nil ]) # Exclude staff-created orders
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
                .where(role: [ "staff", "admin" ])
                .where(restaurant_id: current_restaurant.id)

    # Format the response
    creators = @users.map do |user|
      {
        id: "user_#{user.id}",
        name: "#{user.first_name} #{user.last_name}",
        type: "user",
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
                                   .where(staff_created: [ false, nil ]) # Exclude staff-created orders
                                   .order(created_at: :desc)
    else
      # First-time user case: Only return orders that haven't been acknowledged by anyone
      # OR orders that came in after the last global acknowledgment
      unacknowledged_orders = Order.where("created_at > ?", time_threshold)
                                   .where(staff_created: [ false, nil ]) # Exclude staff-created orders
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

  # POST /orders/:id/notify
  def notify
    order = Order.find(params[:id])

    # Only allow staff or above to send notifications
    unless current_user&.role.in?(%w[admin super_admin staff])
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    notification_type = params[:notification_type] || "order_ready"

    begin
      case notification_type
      when "order_ready"
        if order.status == "ready"
          cooldown_key = "manual_notify_cooldown:order:#{order.id}"
          cooldown_active = begin
            Rails.cache.read(cooldown_key).present?
          rescue StandardError => e
            Rails.logger.warn("Manual notify cooldown cache read failed for order #{order.id}: #{e.class} - #{e.message}")
            false
          end

          if cooldown_active
            response.set_header("Retry-After", "60")
            return render json: {
              success: false,
              message: "Please wait before resending this notification"
            }, status: :too_many_requests
          end

          transition_token = "manual-#{Time.current.utc.iso8601(6)}"
          if enqueue_order_ready_notifications(
               order,
               source: "manual_notify",
               raise_on_failure: false,
               transition_token: transition_token
             )
            begin
              Rails.cache.write(cooldown_key, transition_token, expires_in: 60.seconds)
            rescue StandardError => e
              Rails.logger.warn("Manual notify cooldown cache update failed for order #{order.id}: #{e.class} - #{e.message}")
            end
            render json: {
              success: true,
              message: "Order ready notification queued successfully"
            }, status: :accepted
          else
            render json: {
              success: false,
              message: "Failed to queue order ready notification"
            }, status: :service_unavailable
          end
        else
          render json: {
            success: false,
            message: "Order must be in ready status to send notification"
          }, status: :unprocessable_entity
        end
      else
        render json: {
          success: false,
          message: "Invalid notification type"
        }, status: :bad_request
      end
    rescue StandardError => e
      Rails.logger.error "Failed to send notification for order #{order.id}: #{e.message}"
      render json: {
        success: false,
        message: "Failed to send notification: #{e.message}"
      }, status: :internal_server_error
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
    restaurant = Restaurant.find(params[:restaurant_id] || current_restaurant&.id || 1)

    # Initialize order params before VIP/staff checks.
    params[:order] ||= {}

    # Check for VIP-only restrictions
    if restaurant.vip_only_checkout?
      # Skip VIP validation for admin/staff users OR when using staff modal
      # This allows staff to create orders through StaffOrderModal even when VIP mode is enabled
      is_admin_user = @current_user && @current_user.role.in?(%w[admin super_admin staff])
      is_staff_modal = params[:order][:staff_modal] == true || params[:order][:staff_modal] == "true"

      # Log the VIP mode bypass for debugging
      Rails.logger.info("VIP Mode Check - User: #{@current_user&.id}, Is Admin/Staff: #{is_admin_user}, Is Staff Modal: #{is_staff_modal}, Restaurant: #{restaurant.id}")

      # Only enforce VIP code for non-admin/staff users AND non-staff modal orders
      if !is_admin_user && !is_staff_modal
        vip_code = params[:order][:vip_code]

        if vip_code.blank?
          return render json: {
            error: "This restaurant is currently only accepting orders from VIP guests. Please enter a VIP code.",
            vip_required: true
          }, status: :unprocessable_entity
        end

        # Find the VIP access code to associate with the order
        vip_access_code = VipAccessCode.find_by(restaurant_id: restaurant.id, code: vip_code)

        # Check if the code exists and is available. Usage is incremented inside
        # the order creation transaction so failed orders do not consume VIP codes.
        unless vip_access_code && vip_access_code.available?
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
    new_params[:restaurant_id] ||= params[:restaurant_id] || current_restaurant&.id || 1
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

    # ── PRE-SAVE VALIDATIONS (BUG-7 / HL1-15 and BUG-3 / HL1-11) ──
    # Must run BEFORE create_order because OrderService.create_record persists immediately.
    payload_validation = validate_order_payload_before_persist(params[:order])
    unless payload_validation[:success]
      status = payload_validation.delete(:status) || :unprocessable_entity
      payload_validation.delete(:success)
      return render json: payload_validation, status: status
    end

    # Idempotency guard: if an order already exists for this restaurant+transaction_id,
    # return it instead of creating a duplicate.
    transaction_id = new_params[:transaction_id].presence
    if transaction_id.present? && transaction_id.start_with?("pi_")
      existing_order = Order.where(restaurant_id: new_params[:restaurant_id], transaction_id: transaction_id)
                           .where.not(payment_status: [ "canceled", "refunded" ])
                           .first
      if existing_order.present?
        Rails.logger.warn("Idempotency hit: returning existing order #{existing_order.id} for transaction_id #{transaction_id}")
        return render json: existing_order, status: :ok
      end
    end

    transaction_result = nil
    low_stock_variants = []

    begin
      ActiveRecord::Base.transaction do
        if defined?(vip_access_code) && vip_access_code
          vip_access_code.lock!
          unless vip_access_code.available?
            transaction_result = vip_code_unavailable_response(vip_access_code)
            raise ActiveRecord::Rollback
          end
        end

        @order = order_service.create_order(new_params)

        unless @order.persisted?
          transaction_result = {
            success: false,
            json: { errors: @order.errors.full_messages },
            status: :unprocessable_entity
          }
          raise ActiveRecord::Rollback
        end

        @order.status = "pending"
        unless @order.save
          transaction_result = {
            success: false,
            json: { errors: @order.errors.full_messages },
            status: :unprocessable_entity
          }
          raise ActiveRecord::Rollback
        end

        vip_access_code.use! if defined?(vip_access_code) && vip_access_code

        payment_result = create_initial_order_payment(@order, test_mode)
        unless payment_result[:success]
          transaction_result = {
            success: false,
            json: {
              error: "Payment record creation failed",
              details: payment_result[:errors]
            },
            status: :unprocessable_entity
          }
          raise ActiveRecord::Rollback
        end

        inventory_result = process_initial_order_inventory!(@order, test_mode)
        unless inventory_result[:success]
          transaction_result = {
            success: false,
            json: {
              error: "Inventory processing failed",
              details: inventory_result[:errors]
            },
            status: :unprocessable_entity
          }
          raise ActiveRecord::Rollback
        end

        low_stock_variants = inventory_result[:low_stock_variants]
        transaction_result = { success: true }
      end
    rescue ActiveRecord::RecordNotUnique => e
      idempotency_index = "idx_orders_unique_restaurant_transaction_id_real"
      if transaction_id.present? && transaction_id.start_with?("pi_") && e.message.include?(idempotency_index)
        existing_order = Order.where(restaurant_id: new_params[:restaurant_id], transaction_id: transaction_id)
                             .where.not(payment_status: [ "canceled", "refunded" ])
                             .first
        if existing_order.present?
          Rails.logger.warn("Idempotency race hit: returning existing order #{existing_order.id} for transaction_id #{transaction_id}")
          return render json: existing_order, status: :ok
        end

        Rails.logger.error("RecordNotUnique on #{idempotency_index} for transaction_id #{transaction_id} but no non-canceled/refunded order found")
        return render json: { error: "Duplicate transaction detected. Please contact support." }, status: :conflict
      end

      raise
    rescue StandardError => e
      Rails.logger.error("Order creation failed: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      return render json: { error: "Failed to create order" }, status: :internal_server_error
    end

    unless transaction_result&.dig(:success)
      fallback = {
        success: false,
        json: { error: "Failed to create order" },
        status: :unprocessable_entity
      }
      transaction_result ||= fallback
      return render json: transaction_result[:json], status: transaction_result[:status]
    end

    unless Rails.env.test? || test_mode
      low_stock_variants.each { |variant| StockNotificationJob.perform_later(variant) }
    end

    # Broadcast and notify only after the database transaction has committed.
    WebsocketBroadcastService.broadcast_new_order(@order)
    enqueue_initial_order_notifications(@order)

    render json: @order, status: :created
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
       ([ "refunded" ].include?(permitted_params[:status]) ||
        [ "refunded" ].include?(order.status))
      # Remove status from permitted params to preserve the server-calculated refund status
      # or prevent the frontend from setting a refund status
      Rails.logger.info("Preventing frontend refund status change: #{permitted_params[:status]} -> #{order.status}")
      permitted_params.delete(:status)
    end

    # Pre-validate option inventory if items are being updated
    if permitted_params[:items].present?
      insufficient_options = []

      # Get updated item list
      new_items = permitted_params[:items]

      # Load menu items for validation
      item_ids = new_items.map { |i| i[:id] || i["id"] }.compact.uniq
      menu_items_by_id = MenuItem.where(id: item_ids).index_by(&:id)

      new_items.each do |item|
        item_id = item[:id] || item["id"]
        menu_item = menu_items_by_id[item_id]
        next unless menu_item&.uses_option_level_inventory?

        # Get the option inventory tracking group
        tracking_group = menu_item.option_inventory_tracking_group
        next unless tracking_group

        # Extract customizations and quantity
        customizations = item[:customizations] || item["customizations"] || {}
        quantity_ordered = (item[:quantity] || item["quantity"] || 1).to_i

        # Check inventory for customizations
        customizations.each do |key, value|
          if key.to_s == tracking_group.id.to_s || key.to_s == tracking_group.name
            selected_option = tracking_group.options.find_by(id: value) || tracking_group.options.find_by(name: value)

            if selected_option
              available_stock = selected_option.available_stock

              if available_stock < quantity_ordered
                insufficient_options << {
                  item_name: menu_item.name,
                  option_name: selected_option.name,
                  option_group: tracking_group.name,
                  available: available_stock,
                  requested: quantity_ordered
                }
              end
            end
          end
        end

        # Check selected_options array format
        selected_options = item[:selected_options] || item["selected_options"]
        if selected_options.is_a?(Array)
          selected_options.each do |selected_option_data|
            option_id = selected_option_data[:id] || selected_option_data["id"]
            next unless option_id

            tracked_option = tracking_group.options.find_by(id: option_id)
            if tracked_option
              available_stock = tracked_option.available_stock

              if available_stock < quantity_ordered
                insufficient_options << {
                  item_name: menu_item.name,
                  option_name: tracked_option.name,
                  option_group: tracking_group.name,
                  available: available_stock,
                  requested: quantity_ordered
                }
              end
            end
          end
        end
      end

      if insufficient_options.any?
        return render json: {
          error: "Some selected options have insufficient inventory for this update",
          insufficient_options: insufficient_options
        }, status: :unprocessable_entity
      end
    end

    if order.update(permitted_params)
      # Broadcast the order update via WebSockets
      WebsocketBroadcastService.broadcast_order_update(order)

      # 2) If items changed, process inventory diffs
      # Skip inventory processing if order has refunds (refunds handle their own inventory)
      if permitted_params[:items].present? && !order.has_refunds?
        inventory_success = process_inventory_changes(original_items, order.items, order)
        unless inventory_success
          Rails.logger.error("Inventory processing failed for order update #{order.id}")
          return render json: { error: "Failed to update inventory. Please try again." }, status: :unprocessable_entity
        end
      elsif permitted_params[:items].present? && order.has_refunds?
        Rails.logger.info("Skipping inventory processing for order #{order.id} because it has refunds (refunds handle their own inventory)")
      end

      # -- Existing notification logic below --

      notification_channels = order.restaurant.admin_settings&.dig("notification_channels", "orders") || {}
      restaurant_name = order.restaurant.name
      # Priority: 1) Restaurant phone, 2) Admin SMS sender ID, 3) Restaurant name
      sms_sender = order.restaurant.phone_number.presence ||
                   order.restaurant.admin_settings&.dig("sms_sender_id").presence ||
                   restaurant_name

      # Format phone numbers for ClickSend (remove dashes, keep only digits)
      if sms_sender&.match?(/^[\+\d\-\s\(\)]+$/) && sms_sender.gsub(/\D/, "").length >= 10
        sms_sender = sms_sender.gsub(/\D/, "").gsub(/^1/, "")
      end

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

      # If status changed to 'cancelled', restore inventory for all items
      elsif old_status != "cancelled" && order.status == "cancelled"
        Rails.logger.info("Order #{order.id} was cancelled, restoring inventory for all items")

        if order.items.present?
          order_service = OrderService.new(order.restaurant)
          inventory_result = order_service.revert_order_inventory(order.items, order, current_user)

          if inventory_result[:success]
            Rails.logger.info("Successfully restored inventory for cancelled order #{order.id}: #{inventory_result[:inventory_changes].length} changes")
          else
            Rails.logger.error("Inventory restoration failed for cancelled order #{order.id}: #{inventory_result[:errors]}")
            # Note: We don't fail the cancellation if inventory restoration fails
            # but we log the error for investigation
          end
        end
      end

      # If status changed to 'ready'
      if old_status != "ready" && order.status == "ready"
        enqueue_order_ready_notifications(order, source: "status_update")
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

  def valid_transaction_lookup_secret?(transaction_id, client_secret)
    return false unless transaction_id.to_s.start_with?("pi_") && client_secret.present?

    result = TenantStripeService.new(current_restaurant).retrieve_payment_intent(transaction_id)
    return false unless result[:success]

    result[:payment_intent].client_secret == client_secret
  rescue StandardError => e
    Rails.logger.warn("Order transaction lookup validation failed for #{transaction_id}: #{e.class} - #{e.message}")
    false
  end

  def public_order_confirmation_json(order)
    {
      id: order.id,
      order_number: order.order_number,
      status: order.status,
      total: order.total,
      items: public_order_items(order.items),
      merchandise_items: public_order_items(order.merchandise_items),
      created_at: order.created_at,
      estimated_pickup_time: order.estimated_pickup_time,
      location_name: order.location&.name,
      location_address: order.location&.address,
      requires_advance_notice: order.requires_advance_notice?,
      max_advance_notice_hours: order.max_advance_notice_hours
    }
  end

  def public_order_items(items)
    Array(items).map do |item|
      item_hash = item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item
      next item unless item_hash.respond_to?(:[])

      {
        id: item_hash["id"] || item_hash[:id],
        name: item_hash["name"] || item_hash[:name],
        price: item_hash["price"] || item_hash[:price],
        quantity: item_hash["quantity"] || item_hash[:quantity],
        size: item_hash["size"] || item_hash[:size],
        color: item_hash["color"] || item_hash[:color]
      }.compact
    end
  end

  def menu_items_for_current_restaurant(item_ids)
    return MenuItem.none if item_ids.blank? || current_restaurant.blank?

    MenuItem.unscoped
            .joins(:menu)
            .where(id: item_ids, menus: { restaurant_id: current_restaurant.id })
  end

  def unavailable_options_for_item(menu_item, option_ids)
    return Option.none if menu_item.blank? || option_ids.blank? || current_restaurant.blank?

    Option.unscoped
          .joins(option_group: { menu_item: :menu })
          .where(
            id: option_ids,
            is_available: false,
            option_groups: { menu_item_id: menu_item.id },
            menus: { restaurant_id: current_restaurant.id }
          )
  end

  def tracked_inventory_options_for_item(item, tracking_group)
    selected_options = []

    customizations = item[:customizations] || item["customizations"] || {}
    customizations.each do |key, value|
      next unless key.to_s == tracking_group.id.to_s || key.to_s == tracking_group.name

      Array(value).each do |selected_value|
        selected_option = tracking_group.options.find_by(id: selected_value) ||
                          tracking_group.options.find_by(name: selected_value)
        selected_options << selected_option if selected_option
      end
    end

    item_selected_options = item[:selected_options] || item["selected_options"]
    if item_selected_options.is_a?(Array)
      item_selected_options.each do |selected_option_data|
        option_id = selected_option_data[:id] || selected_option_data["id"]
        next unless option_id

        selected_option = tracking_group.options.find_by(id: option_id)
        selected_options << selected_option if selected_option
      end
    end

    selected_options.uniq(&:id)
  end

  def vip_code_unavailable_response(vip_access_code)
    if vip_access_code.max_uses && vip_access_code.current_uses >= vip_access_code.max_uses
      {
        success: false,
        json: {
          error: "This VIP code has reached its maximum usage limit.",
          vip_required: true
        },
        status: :unprocessable_entity
      }
    else
      {
        success: false,
        json: {
          error: "Invalid VIP code. Please check your code and try again.",
          vip_required: true
        },
        status: :unprocessable_entity
      }
    end
  end

  def create_initial_order_payment(order, test_mode)
    return { success: true, errors: [] } unless order.payment_method.present? && order.payment_amount.present? && order.payment_amount.to_f > 0

    payment_id = order.payment_id || order.transaction_id

    # For Stripe payments, ensure payment_id starts with 'pi_' for test mode
    if order.payment_method == "stripe" && test_mode && (!payment_id || !payment_id.start_with?("pi_"))
      payment_id = "pi_test_#{SecureRandom.hex(16)}"
      unless order.update(payment_id: payment_id)
        return { success: false, errors: order.errors.full_messages.presence || [ "Unable to record test payment id" ] }
      end
      Rails.logger.info("Generated Stripe-like payment_id for test mode: #{payment_id}")
    end

    payment_details = normalize_initial_payment_details(order)

    payment = order.order_payments.create(
      payment_type: "initial",
      amount: order.payment_amount,
      payment_method: order.payment_method,
      status: "paid",
      transaction_id: order.transaction_id || payment_id,
      payment_id: payment_id,
      description: "Initial payment",
      payment_details: payment_details
    )

    unless payment.persisted?
      errors = payment.errors.full_messages.presence || [ "Initial payment could not be recorded" ]
      Rails.logger.error("Initial OrderPayment failed for order #{order.id}: #{errors}")
      return { success: false, errors: errors }
    end

    Rails.logger.info("Created initial OrderPayment record: #{payment.inspect}")
    { success: true, errors: [] }
  end

  def normalize_initial_payment_details(order)
    payment_details = order.payment_details || params.dig(:order, :payment_details)
    payment_details = payment_details.to_unsafe_h if payment_details.respond_to?(:to_unsafe_h)
    payment_details = payment_details.deep_dup if payment_details.respond_to?(:deep_dup)

    if payment_details && payment_details["staffOrderParams"].present?
      staff_params = payment_details["staffOrderParams"]

      payment_details["staffOrderParams"] = {
        "is_staff_order" => order.is_staff_order ? "true" : "false",
        "staff_member_id" => order.staff_member_id.to_s,
        "staff_on_duty" => order.staff_on_duty ? "true" : "false",
        "discount_type" => staff_params["discount_type"].to_s,
        "no_discount" => staff_params["no_discount"].to_s,
        "use_house_account" => order.use_house_account ? "true" : "false",
        "created_by_staff_id" => order.created_by_staff_id.to_s,
        "pre_discount_total" => order.pre_discount_total.to_s
      }
    elsif order.is_staff_order
      payment_details ||= {}
      payment_details["staffOrderParams"] = build_staff_order_payment_details(order)
    end

    payment_details
  end

  def build_staff_order_payment_details(order)
    original_pre_discount_total = if params.dig(:order, :pre_discount_total).present?
                                    params.dig(:order, :pre_discount_total)
    elsif params.dig(:order, :payment_details, :staffOrderParams, :pre_discount_total).present?
                                    params.dig(:order, :payment_details, :staffOrderParams, :pre_discount_total)
    end

    pre_discount_value = if original_pre_discount_total.present?
                           original_pre_discount_total.to_s
    else
                           order.pre_discount_total.to_s
    end

    Rails.logger.info("OrderPayment staffOrderParams: Using pre_discount_total #{pre_discount_value} (from params: #{original_pre_discount_total}, from order: #{order.pre_discount_total})")

    original_discount_type = if params.dig(:order, :discount_type).present?
                               params.dig(:order, :discount_type)
    elsif params.dig(:order, :payment_details, :staffOrderParams, :discount_type).present?
                               params.dig(:order, :payment_details, :staffOrderParams, :discount_type)
    else
                               order.staff_on_duty ? "on_duty" : "off_duty"
    end

    original_no_discount = if params.dig(:order, :no_discount).present?
                             params.dig(:order, :no_discount)
    elsif params.dig(:order, :payment_details, :staffOrderParams, :no_discount).present?
                             params.dig(:order, :payment_details, :staffOrderParams, :no_discount)
    else
                             "false"
    end

    {
      "is_staff_order" => "true",
      "staff_member_id" => order.staff_member_id.to_s,
      "staff_on_duty" => order.staff_on_duty ? "true" : "false",
      "discount_type" => original_discount_type.to_s,
      "no_discount" => original_no_discount.to_s,
      "use_house_account" => order.use_house_account ? "true" : "false",
      "created_by_staff_id" => order.created_by_staff_id.to_s,
      "pre_discount_total" => pre_discount_value
    }
  end

  def process_initial_order_inventory!(order, test_mode)
    result = { success: true, errors: [], low_stock_variants: [] }

    process_initial_merchandise_inventory!(order, result)
    return result unless result[:success]

    process_initial_menu_inventory!(order, result, test_mode)
    result
  end

  def process_initial_merchandise_inventory!(order, result)
    return unless order.merchandise_items.present?

    deductions = []
    remaining_stock_by_variant_id = {}

    order.merchandise_items.each do |item|
      variant_id = item[:merchandise_variant_id] || item["merchandise_variant_id"] || item[:variant_id] || item["variant_id"]
      quantity = (item[:quantity] || item["quantity"] || 1).to_i
      item_name = item[:name] || item["name"] || "Merchandise item"

      variant = MerchandiseVariant.lock
                                  .joins(merchandise_item: :merchandise_collection)
                                  .where(merchandise_collections: { restaurant_id: order.restaurant_id })
                                  .find_by(id: variant_id)

      if variant.nil?
        result[:success] = false
        result[:errors] << "#{item_name}: variant not found"
        next
      end

      remaining_stock = remaining_stock_by_variant_id.fetch(variant.id, variant.stock_quantity)
      if remaining_stock < quantity
        result[:success] = false
        result[:errors] << "#{item_name}: only #{remaining_stock} available (requested #{quantity})"
        next
      end

      remaining_stock_by_variant_id[variant.id] = remaining_stock - quantity
      deductions << { variant: variant, quantity: quantity }
    end

    return unless result[:success]

    deductions.each do |deduction|
      variant = deduction[:variant]
      variant.reduce_stock!(
        deduction[:quantity],
        false, # Don't allow negative stock
        order,
        @current_user
      )
      result[:low_stock_variants] << variant if variant.low_stock?
    end
  end

  def process_initial_menu_inventory!(order, result, test_mode)
    return unless order.items.present?

    Rails.logger.debug("Order items: #{order.items.inspect}")

    order_service = OrderService.new(order.restaurant)
    inventory_result = order_service.process_order_inventory(order.items, order, @current_user, "order")

    unless inventory_result[:success]
      Rails.logger.error("Order creation inventory processing failed: #{inventory_result[:errors]}")
      result[:success] = false
      result[:errors].concat(inventory_result[:errors])
      return
    end

    Rails.logger.info("Successfully processed inventory for order #{order.id}: #{inventory_result[:inventory_changes].length} changes")

    inventory_result[:inventory_changes].each do |change|
      next unless change[:type] == "item_level"

      menu_item = MenuItem.find_by(id: change[:menu_item_id])
      if menu_item&.stock_status == "low_stock" && !Rails.env.test? && !test_mode
        # TODO: implement menu item low-stock notifications if needed
      end
    end
  end

  def enqueue_initial_order_notifications(order)
    notification_channels = order.restaurant.admin_settings&.dig("notification_channels", "orders") || {}
    restaurant_name = order.restaurant.name

    if notification_channels["email"] != false && order.contact_email.present?
      OrderMailer.order_confirmation(order).deliver_later
    end

    return unless notification_channels["sms"] == true && order.contact_phone.present?

    sms_sender = order.restaurant.phone_number.presence ||
                 order.restaurant.admin_settings&.dig("sms_sender_id").presence ||
                 restaurant_name

    if sms_sender&.match?(/^[\+\d\-\s\(\)]+$/) && sms_sender.gsub(/\D/, "").length >= 10
      sms_sender = sms_sender.gsub(/\D/, "").gsub(/^1/, "")
    end

    item_list = order.items.map { |item| "#{item["quantity"]}x #{item["name"]}" }.join(", ")
    if order.merchandise_items.present?
      merch_list = order.merchandise_items.map { |item| "#{item["quantity"]}x #{item["name"]}" }.join(", ")
      item_list += ", " + merch_list unless merch_list.blank?
    end

    msg = <<~TXT.squish
      Hi #{order.contact_name.presence || 'Customer'},
      thanks for ordering from #{restaurant_name}!
      Order ##{order.order_number.presence || order.id}: #{item_list},
      total: $#{sprintf("%.2f", order.total.to_f)}.
      We'll text you an ETA once we start preparing your order!
    TXT

    SendSmsJob.perform_later(to: order.contact_phone, body: msg, from: sms_sender)
  end

  def validate_order_payload_before_persist(order_payload)
    order_payload ||= {}
    order_items = order_payload[:items] || order_payload["items"] || []

    if order_items.present?
      item_ids = order_items.map { |item| (item[:id] || item["id"]).to_i }.select { |id| id > 0 }.uniq
      menu_items_by_id = menu_items_for_current_restaurant(item_ids).index_by(&:id)

      missing_ids = item_ids - menu_items_by_id.keys
      if missing_ids.any?
        return {
          success: false,
          error: "Menu items not found: #{missing_ids.join(', ')}",
          status: :unprocessable_entity
        }
      end

      max_required_notice = menu_items_by_id.values.map(&:advance_notice_hours).compact.max || 0
      pickup_time_value = order_payload[:estimated_pickup_time] || order_payload["estimated_pickup_time"] ||
                          order_payload[:pickup_time] || order_payload["pickup_time"]
      if max_required_notice >= 24
        unless pickup_time_value.present?
          return {
            success: false,
            error: "Pickup time is required for items needing #{max_required_notice} hours advance notice",
            status: :unprocessable_entity
          }
        end

        requested_pickup_time = begin
          pickup_time_value.is_a?(Time) ? pickup_time_value : Time.zone.parse(pickup_time_value.to_s)
        rescue ArgumentError
          nil
        end
        unless requested_pickup_time
          return { success: false, error: "Invalid pickup time", status: :unprocessable_entity }
        end

        earliest_allowed = Time.current + max_required_notice.hours
        if requested_pickup_time < earliest_allowed
          return {
            success: false,
            error: "Earliest pickup time is #{earliest_allowed.strftime('%Y-%m-%d %H:%M')}",
            status: :unprocessable_entity
          }
        end
      end

      requested_item_quantities = Hash.new(0)
      order_items.each do |item|
        item_id = (item[:id] || item["id"]).to_i
        next unless item_id > 0

        requested_item_quantities[item_id] += (item[:quantity] || item["quantity"] || 1).to_i
      end

      stock_errors = []
      requested_item_quantities.each do |item_id, requested_quantity|
        menu_item = menu_items_by_id[item_id]
        next unless menu_item&.enable_stock_tracking

        available = menu_item.available_quantity || 0
        if available < requested_quantity
          stock_errors << "#{menu_item.name}: only #{available} available (requested #{requested_quantity})"
        end
      end

      requested_option_quantities = {}
      unavailable_options = []
      items_with_unavailable_required_groups = []
      insufficient_options = []

      order_items.each do |item|
        item_id = (item[:id] || item["id"]).to_i
        menu_item = menu_items_by_id[item_id]
        quantity = (item[:quantity] || item["quantity"] || 1).to_i

        if menu_item&.has_required_groups_with_unavailable_options?
          items_with_unavailable_required_groups << {
            item_name: menu_item.name,
            item_id: menu_item.id,
            unavailable_groups: menu_item.required_groups_with_unavailable_options.map(&:name)
          }
        end

        selected_options = item[:selected_options] || item["selected_options"]
        if selected_options.is_a?(Array) && selected_options.any?
          option_ids = selected_options.map { |opt| opt[:id] || opt["id"] }.compact
          unavailable_options_for_item(menu_item, option_ids).each do |option|
            unavailable_options << {
              item_name: menu_item&.name || "Unknown item",
              option_name: option.name,
              option_id: option.id
            }
          end
        end

        next unless menu_item&.uses_option_level_inventory?

        tracking_group = menu_item.option_inventory_tracking_group
        next unless tracking_group

        tracked_inventory_options_for_item(item, tracking_group).each do |selected_option|
          requested_option_quantities[selected_option.id] ||= {
            item_name: menu_item.name,
            option: selected_option,
            option_group: tracking_group.name,
            quantity: 0
          }
          requested_option_quantities[selected_option.id][:quantity] += quantity
        end
      end

      requested_option_quantities.each_value do |request|
        available_stock = request[:option].available_stock
        requested_quantity = request[:quantity]
        next unless available_stock < requested_quantity

        insufficient_options << {
          item_name: request[:item_name],
          option_name: request[:option].name,
          option_group: request[:option_group],
          available: available_stock,
          requested: requested_quantity
        }
      end

      if stock_errors.any?
        return { success: false, error: "Insufficient stock", details: stock_errors, status: :unprocessable_entity }
      end

      if items_with_unavailable_required_groups.any?
        return {
          success: false,
          error: "Some items have required option groups with no available options",
          items_with_unavailable_required_groups: items_with_unavailable_required_groups,
          status: :unprocessable_entity
        }
      end

      if unavailable_options.any?
        return {
          success: false,
          error: "Some selected options are currently unavailable",
          unavailable_options: unavailable_options,
          status: :unprocessable_entity
        }
      end

      if insufficient_options.any?
        return {
          success: false,
          error: "Some selected options have insufficient inventory",
          insufficient_options: insufficient_options,
          status: :unprocessable_entity
        }
      end
    end

    merchandise_items = order_payload[:merchandise_items] || order_payload["merchandise_items"] || []
    if merchandise_items.present?
      insufficient_items = []
      requested_merchandise_quantities = {}

      merchandise_items.each do |item|
        variant_id = item[:merchandise_variant_id] || item["merchandise_variant_id"] || item[:variant_id] || item["variant_id"]
        variant = MerchandiseVariant.joins(merchandise_item: :merchandise_collection)
                                    .where(merchandise_collections: { restaurant_id: current_restaurant.id })
                                    .find_by(id: variant_id)
        quantity = (item[:quantity] || item["quantity"] || 1).to_i
        item_name = item[:name] || item["name"] || "Merchandise item"

        if variant.nil?
          insufficient_items << { name: item_name, reason: "variant not found" }
          next
        end

        requested_merchandise_quantities[variant.id] ||= {
          item_name: item_name,
          variant: variant,
          quantity: 0
        }
        requested_merchandise_quantities[variant.id][:quantity] += quantity
      end

      requested_merchandise_quantities.each_value do |request|
        variant = request[:variant]
        quantity = request[:quantity]
        next unless variant.stock_quantity < quantity

        insufficient_items << {
          name: "#{request[:item_name]} (#{variant.color}, #{variant.size})",
          available: variant.stock_quantity,
          requested: quantity
        }
      end

      if insufficient_items.any?
        return {
          success: false,
          error: "Some items have insufficient stock",
          insufficient_items: insufficient_items,
          status: :unprocessable_entity
        }
      end
    end

    { success: true }
  end

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
      :staff_discount_configuration_id, # Add support for configurable staff discounts
      # Handle nested attributes properly
      items: [ :id, :name, :price, :quantity, :notes, :menu_id, :category_id, { customizations: {} } ],
      merchandise_items: [ :id, :name, :price, :quantity, :merchandise_variant_id, :variant_id, :size, :color, :notes ],
      # Allow all payment details attributes to be passed through
      payment_details: {})

    if permitted_params[:merchandise_items].present?
      permitted_params[:merchandise_items].each do |item|
        item[:merchandise_variant_id] ||= item.delete(:variant_id)
      end
    end

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
  # Enhanced inventory change processing using OrderService
  # ----------------------------------------------------
  def process_inventory_changes(original_items, new_items, order)
    Rails.logger.debug("Processing inventory changes for order #{order.id}")
    Rails.logger.debug("Original items: #{original_items.inspect}")
    Rails.logger.debug("New items: #{new_items.inspect}")

    order_service = OrderService.new(order.restaurant)

    begin
      # Step 1: Revert inventory for original items
      if original_items.present?
        revert_result = order_service.revert_order_inventory(original_items, order, @current_user)
        unless revert_result[:success]
          Rails.logger.error("Failed to revert original inventory: #{revert_result[:errors]}")
          return false
        end
        Rails.logger.info("Reverted inventory for #{revert_result[:inventory_changes].length} original items")
      end

      # Step 2: Process inventory for new items
      if new_items.present?
        process_result = order_service.process_order_inventory(new_items, order, @current_user, "order")
        unless process_result[:success]
          Rails.logger.error("Failed to process new inventory: #{process_result[:errors]}")
          # If processing new items fails, we need to restore the original items
          if original_items.present?
            restore_result = order_service.process_order_inventory(original_items, order, @current_user, "order")
            Rails.logger.warn("Attempted to restore original inventory: #{restore_result[:success] ? 'success' : 'failed'}")
          end
          return false
        end
        Rails.logger.info("Processed inventory for #{process_result[:inventory_changes].length} new items")
      end

      Rails.logger.info("Successfully processed inventory changes for order #{order.id}")
      true

    rescue StandardError => e
      Rails.logger.error("Error processing inventory changes: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      false
    end
  end

  # Helper methods for inventory processing (moved to OrderService)

  # Queue order ready notifications via background jobs.
  # Fail-open by default so status transitions never 500 due to Redis/Sidekiq outages.
  def enqueue_order_ready_notifications(order, source:, raise_on_failure: false, transition_token: nil)
    transition_token ||= order.updated_at&.utc&.iso8601(6) || Time.current.utc.iso8601(6)
    OrderReadyNotificationsJob.perform_later(order.id, transition_token)
    Rails.logger.info("Queued order ready notifications for order #{order.id} (source=#{source}, transition_token=#{transition_token})")
    true
  rescue StandardError => e
    Rails.logger.error("Failed to queue order ready notifications for order #{order.id} (source=#{source}): #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n")) if e.backtrace.present?

    raise if raise_on_failure
    false
  end
end
