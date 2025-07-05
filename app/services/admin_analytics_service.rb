# app/services/admin_analytics_service.rb
#
# The AdminAnalyticsService provides methods for generating analytics reports
# with proper tenant isolation. It ensures all data is scoped to the current restaurant.
#
class AdminAnalyticsService < TenantScopedService
  # Get customer orders report with tenant isolation
  # @param start_date [Time] Start date for the report
  # @param end_date [Time] End date for the report
  # @param created_by_user_id [String, nil] Optional filter for staff orders by user who created them
  # @return [Hash] Customer orders report data
  def customer_orders_report(start_date, end_date, created_by_user_id = nil)
    # Ensure end_date includes the full day
    end_date = end_date.end_of_day
    
    # Get orders with tenant isolation, including staff member and user associations
    orders = scope_query(Order)
      .includes(:user, :staff_member)
      .where(created_at: start_date..end_date)
      .where.not(status: "cancelled")
    
    # Separate orders into three categories based on staff_created flag
    customer_orders = orders.where(staff_created: [false, nil]).where.not(user_id: nil)
    guest_orders = orders.where(staff_created: [false, nil]).where(user_id: nil)
    staff_orders = orders.where(staff_created: true)
    
    # Apply user filter if provided
    if created_by_user_id.present?
      staff_orders = staff_orders.where(created_by_user_id: created_by_user_id)
    end
    
    # Process Customer Orders (registered users, not staff-created)
    customer_grouped = customer_orders.group_by(&:user_id)
    customer_report = customer_grouped.map do |user_id, orders_in_group|
      generate_order_group_data(orders_in_group, 'customer')
    end
    
    # Process Guest Orders (no user_id, not staff-created)
    guest_grouped = guest_orders.group_by do |order|
      name_str  = order.contact_name.to_s.strip.downcase
      phone_str = order.contact_phone.to_s.strip.downcase
      email_str = order.contact_email.to_s.strip.downcase
      "GUEST_#{name_str}_#{phone_str}_#{email_str}"
    end
    guest_report = guest_grouped.map do |_group_key, orders_in_group|
      generate_order_group_data(orders_in_group, 'guest')
    end
    
    # Process Staff Orders (staff_created = true)
    # Group by created_by_user_id to track which employee made the orders
    staff_grouped = staff_orders.group_by(&:created_by_user_id)
    staff_report = staff_grouped.map do |created_by_user_id, orders_in_group|
      generate_order_group_data(orders_in_group, 'staff', created_by_user_id)
    end
    
    {
      start_date: start_date,
      end_date: end_date,
      customer_orders: customer_report,
      guest_orders: guest_report,
      staff_orders: staff_report,
      restaurant_id: @restaurant.id,
      restaurant_name: @restaurant.name,
      # Keep legacy format for backward compatibility
      results: customer_report + guest_report + staff_report,
      # Include filter info
      staff_member_filter: created_by_user_id
    }
  end
  
  # Get revenue trend report with tenant isolation
  # @param interval [String] Time interval for grouping (30min, hour, day, week, month)
  # @param start_date [Time] Start date for the report
  # @param end_date [Time] End date for the report
  # @return [Hash] Revenue trend report data
  def revenue_trend_report(interval, start_date, end_date)
    # Ensure end_date includes the full day
    end_date = end_date.end_of_day
    
    # Get orders with tenant isolation
    orders = scope_query(Order)
      .where.not(status: "cancelled")
      .where(created_at: start_date..end_date)
    
    # Calculate net revenue for each order (total - refunded amount)
    # Since we need to account for refunds, we'll process this in Ruby rather than pure SQL
    order_data = orders.includes(:order_payments).map do |order|
      net_revenue = order.total - order.total_refunded
      { order: order, net_revenue: net_revenue }
    end
    
    # Group by the specified interval
    case interval
    when "30min"
      # Group by 30-minute intervals
      grouped_data = order_data.group_by do |data|
        time = data[:order].created_at
        hour_start = time.beginning_of_hour
        thirty_min_interval = (time.min >= 30) ? 30 : 0
        hour_start + thirty_min_interval.minutes
      end
      
      results = grouped_data.map do |time_interval, data_array|
        revenue = data_array.sum { |d| d[:net_revenue] }
        { time_interval: time_interval, revenue: revenue }
      end.sort_by { |r| r[:time_interval] }
      
    when "hour"
      # Group by hour
      grouped_data = order_data.group_by do |data|
        data[:order].created_at.beginning_of_hour
      end
      
      results = grouped_data.map do |time_interval, data_array|
        revenue = data_array.sum { |d| d[:net_revenue] }
        { time_interval: time_interval, revenue: revenue }
      end.sort_by { |r| r[:time_interval] }
      
    when "week"
      grouped_data = order_data.group_by do |data|
        date = data[:order].created_at
        [date.year, date.cweek]
      end
      
      results = grouped_data.map do |(year, week), data_array|
        revenue = data_array.sum { |d| d[:net_revenue] }
        { yr: year, wk: week, revenue: revenue }
      end.sort_by { |r| [r[:yr], r[:wk]] }
      
    when "month"
      grouped_data = order_data.group_by do |data|
        date = data[:order].created_at
        [date.year, date.month]
      end
      
      results = grouped_data.map do |(year, month), data_array|
        revenue = data_array.sum { |d| d[:net_revenue] }
        { yr: year, mon: month, revenue: revenue }
      end.sort_by { |r| [r[:yr], r[:mon]] }
      
    else # 'day'
      grouped_data = order_data.group_by do |data|
        data[:order].created_at.to_date
      end
      
      results = grouped_data.map do |date, data_array|
        revenue = data_array.sum { |d| d[:net_revenue] }
        { date: date, revenue: revenue }
      end.sort_by { |r| r[:date] }
    end
    
    # Format the data for the frontend
    data = results.map do |row|
      if interval == "30min" || interval == "hour"
        time_str = row[:time_interval].strftime("%Y-%m-%d %H:%M")
        { label: time_str, revenue: row[:revenue].to_f.round(2) }
      elsif interval == "day"
        { label: row[:date], revenue: row[:revenue].to_f.round(2) }
      elsif interval == "week"
        { label: "Year #{row[:yr]} - Week #{row[:wk]}", revenue: row[:revenue].to_f.round(2) }
      else
        { label: "Year #{row[:yr]}, Month #{row[:mon]}", revenue: row[:revenue].to_f.round(2) }
      end
    end
    
    {
      start_date: start_date,
      end_date: end_date,
      interval: interval,
      data: data,
      restaurant_id: @restaurant.id,
      restaurant_name: @restaurant.name
    }
  end
  
  # Get top items report with tenant isolation
  # @param limit [Integer] Number of top items to return
  # @param start_date [Time] Start date for the report
  # @param end_date [Time] End date for the report
  # @return [Hash] Top items report data
  def top_items_report(limit, start_date, end_date)
    # Ensure end_date includes the full day
    end_date = end_date.end_of_day
    
    # Get orders with tenant isolation
    orders = scope_query(Order)
      .includes(:order_payments)
      .where.not(status: "cancelled")
      .where(created_at: start_date..end_date)
    
    # Extract and group items, accounting for refunds
    all_items = []
    
    orders.each do |order|
      # Get refunded items for this order
      refunded_items_data = order.refunds.flat_map do |refund|
        refund.get_refunded_items || []
      end
      
      # Create a hash of refunded quantities by item name
      refunded_quantities = {}
      refunded_items_data.each do |refunded_item|
        item_name = refunded_item["name"] || refunded_item[:name]
        quantity = refunded_item["quantity"] || refunded_item[:quantity] || 0
        refunded_quantities[item_name] = (refunded_quantities[item_name] || 0) + quantity.to_i
      end
      
      # Process order items, subtracting refunded quantities
      order.items.each do |item|
        item_name = item["name"] || "Unknown"
        total_quantity = item["quantity"] || 1
        refunded_quantity = refunded_quantities[item_name] || 0
        net_quantity = [total_quantity.to_i - refunded_quantity, 0].max
        
        # Only include items with net positive quantity
        if net_quantity > 0
          all_items << {
            "name" => item_name,
            "quantity" => net_quantity,
            "price" => item["price"] || 0
          }
        end
      end
    end
    
    # Group items by name
    grouped = all_items.group_by { |i| i["name"] || "Unknown" }
    
    # Calculate quantities and revenue
    results = grouped.map do |item_name, lines|
      qty = lines.sum { |ln| ln["quantity"] || 1 }
      rev = lines.sum { |ln| (ln["price"] || 0).to_f * (ln["quantity"] || 1) }
      { item_name: item_name, quantity_sold: qty, revenue: rev.round(2) }
    end
    
    # Get the top items by revenue
    top = results.sort_by { |r| -r[:revenue] }.first(limit)
    
    {
      start_date: start_date,
      end_date: end_date,
      top_items: top,
      restaurant_id: @restaurant.id,
      restaurant_name: @restaurant.name
    }
  end
  
  # Get income statement report with tenant isolation
  # @param year [Integer] Year for the report
  # @return [Hash] Income statement report data
  def income_statement_report(year)
    year_start = Date.new(year, 1, 1).beginning_of_day
    year_end   = year_start.end_of_year
    
    # Get orders with tenant isolation
    orders = scope_query(Order)
      .includes(:order_payments)
      .where.not(status: "cancelled")
      .where(created_at: year_start..year_end)
    
    # Calculate net revenue by month accounting for refunds
    monthly_data = {}
    
    orders.each do |order|
      month = order.created_at.month
      net_revenue = order.total - order.total_refunded
      monthly_data[month] = (monthly_data[month] || 0) + net_revenue
    end
    
    # Month names for reference
    month_names = %w[January February March April May June July August September October November December]
    
    # Format the data for the frontend
    data = (1..12).map do |month|
      {
        month: month_names[month - 1],
        revenue: (monthly_data[month] || 0).to_f.round(2)
      }
    end
    
    {
      year: year,
      income_statement: data,
      restaurant_id: @restaurant.id,
      restaurant_name: @restaurant.name
    }
  end
  
  # Get user signups report with tenant isolation
  # @param start_date [Time] Start date for the report
  # @param end_date [Time] End date for the report
  # @return [Hash] User signups report data
  def user_signups_report(start_date, end_date)
    # Ensure end_date includes the full day
    end_date = end_date.end_of_day
    
    # Get users with tenant isolation
    daily_signups = scope_query(User)
      .where(created_at: start_date..end_date)
      .group("DATE(created_at)")
      .select("DATE(created_at) as date, COUNT(*) as count")
      .order("date")
    
    # Format the data for the frontend
    data = daily_signups.map do |row|
      {
        date: row.date.to_s,
        count: row.count.to_i
      }
    end
    
    {
      start_date: start_date,
      end_date: end_date,
      signups: data,
      restaurant_id: @restaurant.id,
      restaurant_name: @restaurant.name
    }
  end
  
  # Get user activity heatmap report with tenant isolation
  # @param start_date [Time] Start date for the report
  # @param end_date [Time] End date for the report
  # @return [Hash] User activity heatmap report data
  def user_activity_heatmap_report(start_date, end_date)
    # Ensure end_date includes the full day
    end_date = end_date.end_of_day
    
    # Get orders with tenant isolation
    activity_data = scope_query(Order)
      .where(created_at: start_date..end_date)
      .where.not(status: "cancelled")
      .group("EXTRACT(DOW FROM created_at)")
      .group("EXTRACT(HOUR FROM created_at)")
      .count
    
    # Transform the data for the frontend
    heatmap_data = []
    
    # Initialize with zeros for all day/hour combinations
    (0..6).each do |day|
      (0..23).each do |hour|
        count = 0
        
        # Find the matching key in activity_data
        activity_data.each do |key, value|
          if key[0].to_i == day && key[1].to_i == hour
            count = value
            break
          end
        end
        
        heatmap_data << {
          day: day,
          hour: hour,
          value: count
        }
      end
    end
    
    # Day names for reference
    day_names = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
    
    {
      start_date: start_date,
      end_date: end_date,
      day_names: day_names,
      heatmap: heatmap_data,
      restaurant_id: @restaurant.id,
      restaurant_name: @restaurant.name
    }
  end

  private

  # Generate standardized order group data for different order types
  def generate_order_group_data(orders_in_group, order_type, created_by_user_id = nil)
    # Calculate total spent accounting for refunds
    total_spent = orders_in_group.sum { |order| order.total - order.total_refunded }
    order_count = orders_in_group.size
    
    all_items = orders_in_group.flat_map(&:items)
    
    # Group by both name and customizations to handle items with different customizations separately
    item_details = all_items.group_by do |item|
      customizations_key = item["customizations"]&.to_s || ""
      "#{item["name"] || "Unknown"}|#{customizations_key}"
    end.map do |_group_key, lines|
      first_item = lines.first
      
      {
        name: first_item["name"] || "Unknown",
        quantity: lines.sum { |ln| ln["quantity"] || 1 },
        customizations: first_item["customizations"]
      }
    end
    
    first_order = orders_in_group.first
    
    case order_type
    when 'customer'
      user_obj = first_order.user
      user_name = user_obj&.full_name.presence || user_obj&.email || "Unknown User"
      user_id = user_obj.id
      
      {
        user_id: user_id,
        user_name: user_name,
        total_spent: total_spent.to_f.round(2),
        order_count: order_count,
        items: item_details,
        order_type: 'customer'
      }
      
    when 'guest'
      fallback_name = first_order.contact_name.presence ||
                      first_order.contact_phone.presence ||
                      first_order.contact_email.presence ||
                      "Unknown Guest"
      
      {
        user_id: nil,
        user_name: "Guest (#{fallback_name})",
        total_spent: total_spent.to_f.round(2),
        order_count: order_count,
        items: item_details,
        order_type: 'guest'
      }
      
    when 'staff'
      # For staff orders, we want to show who created them (the employee)
      created_by_user = created_by_user_id ? User.find_by(id: created_by_user_id) : nil
      
      if created_by_user
        creator_name = "Staff: #{created_by_user.full_name || created_by_user.email}"
      else
        creator_name = "Staff: Unknown Employee"
      end
      
      {
        user_id: created_by_user_id,
        user_name: creator_name,
        total_spent: total_spent.to_f.round(2),
        order_count: order_count,
        items: item_details,
        order_type: 'staff',
        created_by_user_id: created_by_user_id,
        # Include additional staff order info
        staff_order_details: {
          total_orders_for_staff: order_count,
          average_order_value: (total_spent.to_f / order_count).round(2),
          employee_name: created_by_user&.full_name,
          employee_email: created_by_user&.email
        }
      }
    end
  end
end
