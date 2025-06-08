# app/queries/order_query.rb

class OrderQuery
  # Initialize with a base relation (defaults to all orders)
  def initialize(relation = Order.all)
    @relation = relation
  end

  # Main entry point - applies all filters based on params
  def call(params = {})
    result = @relation

    # Apply policy scope if provided
    result = apply_policy_scope(result, params[:current_user]) if params[:current_user]

    # Apply individual filters based on params
    result = filter_by_restaurant(result, params[:restaurant_id]) if params[:restaurant_id].present?
    result = filter_by_status(result, params[:status]) if params[:status].present?
    result = filter_by_location(result, params[:location_id]) if params[:location_id].present?
    result = filter_by_online_orders(result, params[:online_orders_only]) if params[:online_orders_only].present?
    result = filter_by_staff_member(result, params[:staff_member_id]) if params[:staff_member_id].present?
    result = filter_by_date_range(result, params[:date_from], params[:date_to]) if params[:date_from].present? && params[:date_to].present?
    result = filter_by_search(result, params[:search]) if params[:search].present?

    # Apply default filters if no filters were applied and default_filters flag is true
    result = apply_default_filters(result) if params[:default_filters] && params == {current_user: params[:current_user], default_filters: true}

    # Apply sorting
    result = apply_sorting(result, params[:sort_by], params[:sort_direction])

    result
  end

  # Returns the total count for pagination
  def total_count
    @relation.count
  end

  # Returns paginated results using Kaminari
  def paginate(page = 1, per_page = 10)
    # Use Kaminari for pagination with explicit page and per_page
    @relation = @relation.page(page).per(per_page)
    self
  end

  # Returns the relation with eager loaded associations
  def with_includes(*includes)
    @relation = @relation.includes(*includes)
    self
  end

  private

  # Apply policy scope based on user
  def apply_policy_scope(relation, user)
    # Use Pundit's policy_scope directly on the relation
    Pundit::PolicyFinder.new(relation).scope.new(user, relation).resolve
  end

  # Filter by restaurant_id
  def filter_by_restaurant(relation, restaurant_id)
    relation.where(restaurant_id: restaurant_id)
  end

  # Filter by status
  def filter_by_status(relation, status)
    relation.where(status: status)
  end

  # Filter by location_id
  def filter_by_location(relation, location_id)
    relation.where(location_id: location_id)
  end

  # Filter for online orders only (customer orders)
  def filter_by_online_orders(relation, online_orders_only)
    return relation unless online_orders_only == 'true'
    relation.where(staff_created: false)
  end

  # Filter by staff member or user
  def filter_by_staff_member(relation, staff_member_id)
    if staff_member_id.to_s.include?('user_')
      # If the ID starts with 'user_', it's a user ID
      user_id = staff_member_id.to_s.gsub('user_', '')
      # Only filter by user_id for user-created orders
      relation.where(created_by_user_id: user_id)
    else
      # This is a staff member ID
      relation.where(created_by_staff_id: staff_member_id)
    end
  end

  # Filter by date range with timezone consideration (Guam time: UTC+10)
  def filter_by_date_range(relation, date_from_str, date_to_str)
    begin
      # Validate date format before parsing
      raise ArgumentError, "Invalid date format for date_from: #{date_from_str}" unless valid_date_format?(date_from_str)
      raise ArgumentError, "Invalid date format for date_to: #{date_to_str}" unless valid_date_format?(date_to_str)
      
      # Parse dates with timezone consideration
      date_from = Time.zone.parse(date_from_str)
      date_to = Time.zone.parse(date_to_str)
      
      # Ensure dates are in logical order
      if date_from > date_to
        Rails.logger.warn("Date range has from > to: #{date_from_str} > #{date_to_str}. Swapping dates.")
        date_from, date_to = date_to, date_from
      end

      # For dates in UTC (ending with Z), adjust for Guam timezone
      if date_from_str.end_with?('Z') || date_to_str.end_with?('Z')
        # For custom date range, ensure we're using the full day in Guam time
        date_from = date_from.beginning_of_day
        date_to = date_to.end_of_day
      end

      # Ensure we capture all orders within the full range
      date_from = date_from.beginning_of_day - 1.second
      date_to = date_to.end_of_day + 1.second

      # Log the applied date range for debugging
      Rails.logger.debug("Filtering orders with date range: #{date_from} to #{date_to}")
      
      relation.where(created_at: date_from..date_to)
    rescue ArgumentError => e
      # Re-raise for controller to handle with proper HTTP status
      raise e
    rescue StandardError => e
      # Log detailed error and re-raise for controller to handle
      Rails.logger.error("Error in date range filter: #{e.message}")
      Rails.logger.error("date_from: #{date_from_str.inspect}, date_to: #{date_to_str.inspect}")
      raise ArgumentError, "Invalid date range parameters: #{e.message}"
    end
  end
  
  # Helper method to validate date string format
  def valid_date_format?(date_str)
    # Basic format validation - should be parseable by Time.zone.parse
    # Accepts ISO8601, RFC2822, and several other common formats
    return false if date_str.nil? || date_str.empty?
    
    begin
      result = Time.zone.parse(date_str)
      return !result.nil?
    rescue
      return false
    end
  end

  # Search functionality
  def filter_by_search(relation, search_term)
    search_term_like = "%#{search_term}%"
    
    # Basic search
    basic_search = relation.where(
      "id::text ILIKE ? OR contact_name ILIKE ? OR contact_email ILIKE ? OR contact_phone ILIKE ? OR special_instructions ILIKE ?",
      search_term_like, search_term_like, search_term_like, search_term_like, search_term_like
    )
    
    # Search in order items requires a join
    order_items_search = Order.joins(:order_items)
                         .where("order_items.name ILIKE ? OR order_items.notes ILIKE ?", 
                                search_term_like, search_term_like)
                         .distinct
                         .pluck(:id)
    
    if order_items_search.any?
      basic_search.or(Order.where(id: order_items_search))
    else
      basic_search
    end
  end

  # Apply default filters (pending orders for today)
  def apply_default_filters(relation)
    today = Time.current.in_time_zone("Guam").beginning_of_day
    tonight = today.end_of_day
    
    relation.where(status: Order::STATUS_PENDING)
           .where(created_at: today..tonight)
  end

  # Apply sorting
  def apply_sorting(relation, sort_by, sort_direction)
    # Default values
    sort_by ||= 'created_at'
    sort_direction ||= 'desc'
    
    # Validate sort parameters to prevent SQL injection
    valid_sort_columns = ['id', 'created_at', 'updated_at', 'status', 'total']
    valid_sort_directions = ['asc', 'desc']
    
    sort_by = 'created_at' unless valid_sort_columns.include?(sort_by)
    sort_direction = 'desc' unless valid_sort_directions.include?(sort_direction)
    
    relation.order("#{sort_by} #{sort_direction}")
  end
end
