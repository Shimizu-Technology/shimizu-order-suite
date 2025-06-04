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
  
  # Find all fundraiser orders for the current restaurant with optional filtering
  # @param filters [Hash] Additional filters to apply to the query
  # @return [ActiveRecord::Relation] A relation of fundraiser orders for the current restaurant
  def find_fundraiser_orders(filters = {})
    find_records(Order, filters.merge(is_fundraiser_order: true))
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
  # @param include_fundraiser_orders [Boolean] Whether to include fundraiser orders
  # @return [Hash] Order statistics
  def get_order_statistics(start_date = 30.days.ago, end_date = Time.current, include_fundraiser_orders = true)
    # Ensure we're working with the right time objects
    start_time = start_date.beginning_of_day
    end_time = end_date.end_of_day
    
    # Get orders in the date range
    orders = scope_query(Order)
      .where(created_at: start_time..end_time)
      .where.not(status: "cancelled")
    
    # Exclude fundraiser orders if specified
    unless include_fundraiser_orders
      orders = orders.where(is_fundraiser_order: [false, nil])
    end
    
    # Calculate statistics
    total_count = orders.count
    total_revenue = orders.sum(:total)
    average_order_value = total_count > 0 ? total_revenue / total_count : 0
    
    # Get fundraiser-specific statistics if included
    fundraiser_stats = {}
    if include_fundraiser_orders
      fundraiser_orders = orders.where(is_fundraiser_order: true)
      fundraiser_count = fundraiser_orders.count
      fundraiser_revenue = fundraiser_orders.sum(:total)
      
      fundraiser_stats = {
        fundraiser_count: fundraiser_count,
        fundraiser_revenue: fundraiser_revenue,
        fundraiser_percentage: total_count > 0 ? (fundraiser_count.to_f / total_count * 100).round(2) : 0
      }
    end
    
    {
      total_count: total_count,
      total_revenue: total_revenue,
      average_order_value: average_order_value,
      start_date: start_time,
      end_date: end_time,
      restaurant_id: @restaurant.id,
      restaurant_name: @restaurant.name,
      fundraiser_stats: fundraiser_stats
    }
  end
  
  # Get fundraiser order statistics for the current restaurant
  # @param fundraiser_id [Integer] ID of the fundraiser to get statistics for (optional)
  # @param start_date [Date] Start date for the statistics
  # @param end_date [Date] End date for the statistics
  # @return [Hash] Fundraiser order statistics
  def get_fundraiser_statistics(fundraiser_id = nil, start_date = 30.days.ago, end_date = Time.current)
    # Ensure we're working with the right time objects
    start_time = start_date.beginning_of_day
    end_time = end_date.end_of_day
    
    # Get fundraiser orders in the date range
    orders = scope_query(Order)
      .where(created_at: start_time..end_time)
      .where(is_fundraiser_order: true)
      .where.not(status: "cancelled")
    
    # Filter by fundraiser if specified
    if fundraiser_id.present?
      orders = orders.where(fundraiser_id: fundraiser_id)
    end
    
    # Calculate statistics
    total_count = orders.count
    total_revenue = orders.sum(:total)
    average_order_value = total_count > 0 ? total_revenue / total_count : 0
    
    # Get statistics by fundraiser
    fundraiser_breakdown = {}
    if fundraiser_id.nil?
      fundraiser_breakdown = Fundraiser.joins(:orders)
        .where(orders: { created_at: start_time..end_time, is_fundraiser_order: true })
        .where.not(orders: { status: "cancelled" })
        .where(restaurant_id: @restaurant.id)
        .group('fundraisers.id, fundraisers.name')
        .select('fundraisers.id, fundraisers.name, COUNT(orders.id) as order_count, SUM(orders.total) as total_revenue')
    end
    
    # Get statistics by participant
    participant_breakdown = FundraiserParticipant.joins(:orders)
      .where(orders: { created_at: start_time..end_time, is_fundraiser_order: true })
      .where.not(orders: { status: "cancelled" })
      .where(fundraiser_id: fundraiser_id || Fundraiser.where(restaurant_id: @restaurant.id).pluck(:id))
      .group('fundraiser_participants.id, fundraiser_participants.name')
      .select('fundraiser_participants.id, fundraiser_participants.name, COUNT(orders.id) as order_count, SUM(orders.total) as total_revenue')
    
    {
      total_count: total_count,
      total_revenue: total_revenue,
      average_order_value: average_order_value,
      start_date: start_time,
      end_date: end_time,
      restaurant_id: @restaurant.id,
      fundraiser_id: fundraiser_id,
      fundraiser_breakdown: fundraiser_breakdown,
      participant_breakdown: participant_breakdown
    }
  end
  
  # Process a fundraiser order
  # @param order [Order] The fundraiser order to process
  # @return [Boolean] Whether the processing was successful
  def process_fundraiser_order(order)
    return false unless order.is_fundraiser_order?
    
    # Ensure the order belongs to the current restaurant
    ensure_record_belongs_to_restaurant(order)
    
    # Ensure the fundraiser exists and is active
    fundraiser = Fundraiser.find_by(id: order.fundraiser_id)
    return false if fundraiser.nil? || !fundraiser.active?
    
    # Process the order
    order.status = "pending"
    order.payment_status = "completed"
    order.save
    
    # Create the initial payment record
    if order.payment_method.present? && order.payment_amount.present? && order.payment_amount.to_f > 0
      payment_id = order.payment_id || order.transaction_id || "FUNDRAISER-#{SecureRandom.hex(8)}"
      
      order.order_payments.create(
        payment_type: "initial",
        amount: order.payment_amount,
        payment_method: order.payment_method,
        status: "paid",
        transaction_id: order.transaction_id || payment_id,
        payment_id: payment_id,
        description: "Initial payment for fundraiser order"
      )
    end
    
    # Return success
    true
  end
  
  private
  
  # Additional private methods specific to order operations can be added here
end
