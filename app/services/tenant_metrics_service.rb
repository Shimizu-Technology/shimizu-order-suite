# app/services/tenant_metrics_service.rb
#
# The TenantMetricsService is responsible for collecting, aggregating, and
# reporting tenant-specific metrics for monitoring and analytics purposes.
# It provides methods to track various tenant activities and resource usage.
#
class TenantMetricsService
  class << self
    # Track a new order for a tenant
    # @param restaurant [Restaurant] the tenant restaurant
    # @param order [Order] the order being tracked
    # @return [void]
    def track_order(restaurant, order)
      return unless restaurant && order
      
      # Increment order count in Redis
      increment_counter("tenant:#{restaurant.id}:orders:count")
      
      # Track order value
      increment_counter("tenant:#{restaurant.id}:orders:value", order.total_amount.to_i)
      
      # Track order items count
      increment_counter("tenant:#{restaurant.id}:order_items:count", order.order_items.count)
      
      # Track payment method usage
      if order.payment_method.present?
        increment_counter("tenant:#{restaurant.id}:payment_method:#{order.payment_method}")
      end
      
      # Log the order for analytics
      log_tenant_event(restaurant, 'order_created', {
        order_id: order.id,
        value: order.total_amount,
        items_count: order.order_items.count,
        payment_method: order.payment_method
      })
    end
    
    # Track a user login for a tenant
    # @param restaurant [Restaurant] the tenant restaurant
    # @param user [User] the user who logged in
    # @return [void]
    def track_user_login(restaurant, user)
      return unless restaurant && user
      
      # Increment login count
      increment_counter("tenant:#{restaurant.id}:user_logins")
      
      # Track unique user logins (daily)
      date_key = Date.today.strftime('%Y-%m-%d')
      redis.sadd("tenant:#{restaurant.id}:unique_logins:#{date_key}", user.id)
      
      # Log the login for analytics
      log_tenant_event(restaurant, 'user_login', {
        user_id: user.id,
        device: user.last_login_device,
        ip_address: user.last_login_ip
      })
    end
    
    # Track API request metrics
    # @param restaurant [Restaurant] the tenant restaurant
    # @param controller [String] the controller name
    # @param action [String] the action name
    # @param duration [Float] the request duration in milliseconds
    # @return [void]
    def track_api_request(restaurant, controller, action, duration)
      return unless restaurant
      
      # Increment request count
      increment_counter("tenant:#{restaurant.id}:api_requests")
      
      # Track endpoint usage
      endpoint = "#{controller}##{action}"
      increment_counter("tenant:#{restaurant.id}:endpoint:#{endpoint}")
      
      # Track request duration (using Redis sorted set for percentile calculations)
      redis.zadd("tenant:#{restaurant.id}:request_duration:#{endpoint}", duration, "#{Time.now.to_i}:#{SecureRandom.hex(4)}")
      
      # Trim the sorted set to prevent unbounded growth
      redis.zremrangebyrank("tenant:#{restaurant.id}:request_duration:#{endpoint}", 0, -1001) if rand < 0.1
    end
    
    # Get daily active users for a tenant
    # @param restaurant [Restaurant] the tenant restaurant
    # @param date [Date] the date to check (defaults to today)
    # @return [Integer] count of daily active users
    def daily_active_users(restaurant, date = Date.today)
      return 0 unless restaurant
      
      date_key = date.strftime('%Y-%m-%d')
      redis.scard("tenant:#{restaurant.id}:unique_logins:#{date_key}").to_i
    end
    
    # Get monthly active users for a tenant
    # @param restaurant [Restaurant] the tenant restaurant
    # @param month [Date] the month to check (defaults to current month)
    # @return [Integer] count of monthly active users
    def monthly_active_users(restaurant, month = Date.today.beginning_of_month)
      return 0 unless restaurant
      
      # Get all dates in the month
      start_date = month.beginning_of_month
      end_date = month.end_of_month
      
      # Union all daily active user sets for the month
      temp_key = "tenant:#{restaurant.id}:mau:#{start_date.strftime('%Y-%m')}"
      date_range = (start_date..end_date).map do |date|
        "tenant:#{restaurant.id}:unique_logins:#{date.strftime('%Y-%m-%d')}"
      end
      
      # Only proceed if we have data
      return 0 if date_range.empty?
      
      # Use Redis SUNIONSTORE to get the union of all daily sets
      redis.sunionstore(temp_key, *date_range)
      count = redis.scard(temp_key).to_i
      
      # Clean up the temporary key
      redis.expire(temp_key, 60) # expire after 1 minute
      
      count
    end
    
    # Get tenant usage statistics for a given period
    # @param restaurant [Restaurant] the tenant restaurant
    # @param start_date [Date] the start date
    # @param end_date [Date] the end date
    # @return [Hash] tenant usage statistics
    def tenant_usage_stats(restaurant, start_date = 30.days.ago.to_date, end_date = Date.today)
      return {} unless restaurant
      
      # Collect order statistics
      order_count = Order.where(restaurant_id: restaurant.id)
                         .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
                         .count
                         
      order_value = Order.where(restaurant_id: restaurant.id)
                         .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
                         .sum(:total_amount)
      
      # Collect user statistics
      user_count = User.where(restaurant_id: restaurant.id).count
      
      # Collect API usage statistics
      api_requests = get_counter_value("tenant:#{restaurant.id}:api_requests")
      
      # Collect resource usage
      menu_items_count = MenuItem.where(restaurant_id: restaurant.id).count
      categories_count = Category.where(restaurant_id: restaurant.id).count
      
      # Return compiled statistics
      {
        period: {
          start_date: start_date,
          end_date: end_date,
          days: (end_date - start_date).to_i + 1
        },
        orders: {
          count: order_count,
          value: order_value,
          average_value: order_count > 0 ? (order_value / order_count).round(2) : 0
        },
        users: {
          total: user_count,
          dau: daily_active_users(restaurant),
          mau: monthly_active_users(restaurant)
        },
        api_usage: {
          total_requests: api_requests
        },
        resources: {
          menu_items: menu_items_count,
          categories: categories_count
        }
      }
    end
    
    # Get tenant health metrics
    # @param restaurant [Restaurant] the tenant restaurant
    # @return [Hash] tenant health metrics
    def tenant_health_metrics(restaurant)
      return {} unless restaurant
      
      # Calculate error rate
      total_requests = get_counter_value("tenant:#{restaurant.id}:api_requests").to_f
      error_requests = get_counter_value("tenant:#{restaurant.id}:api_errors").to_f
      error_rate = total_requests > 0 ? (error_requests / total_requests * 100).round(2) : 0
      
      # Calculate average response time
      avg_response_time = calculate_average_response_time(restaurant)
      
      # Get recent order success rate
      recent_orders = Order.where(restaurant_id: restaurant.id)
                           .where(created_at: 24.hours.ago..Time.current)
      
      successful_orders = recent_orders.where.not(status: ['failed', 'cancelled']).count
      order_success_rate = recent_orders.count > 0 ? (successful_orders.to_f / recent_orders.count * 100).round(2) : 100
      
      # Return health metrics
      {
        error_rate: error_rate,
        avg_response_time: avg_response_time,
        order_success_rate: order_success_rate,
        status: determine_health_status(error_rate, avg_response_time, order_success_rate)
      }
    end
    
    # Track an error for a tenant
    # @param restaurant [Restaurant] the tenant restaurant
    # @param error_type [String] the type of error
    # @param details [Hash] additional error details
    # @return [void]
    def track_error(restaurant, error_type, details = {})
      return unless restaurant
      
      # Increment error count
      increment_counter("tenant:#{restaurant.id}:api_errors")
      
      # Track specific error type
      increment_counter("tenant:#{restaurant.id}:error:#{error_type}")
      
      # Log the error for analytics
      log_tenant_event(restaurant, 'error', {
        error_type: error_type,
        details: details
      })
    end
    
    # Get all tenants with potential issues
    # @return [Array<Hash>] list of tenants with health issues
    def tenants_with_issues
      Restaurant.all.map do |restaurant|
        health = tenant_health_metrics(restaurant)
        next if health[:status] == 'healthy'
        
        {
          id: restaurant.id,
          name: restaurant.name,
          health: health
        }
      end.compact
    end
    
    private
    
    def redis
      @redis ||= Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
    end
    
    def increment_counter(key, increment = 1)
      redis.incrby(key, increment)
    end
    
    def get_counter_value(key)
      redis.get(key).to_i
    end
    
    def log_tenant_event(restaurant, event_type, data = {})
      # Store event in database for long-term analytics
      TenantEvent.create!(
        restaurant_id: restaurant.id,
        event_type: event_type,
        data: data
      )
    rescue => e
      # Log error but don't fail the operation
      Rails.logger.error("Failed to log tenant event: #{e.message}")
    end
    
    def calculate_average_response_time(restaurant)
      # Sample a few endpoints to get average response time
      endpoints = redis.keys("tenant:#{restaurant.id}:request_duration:*")
      return 0 if endpoints.empty?
      
      # Take up to 5 random endpoints
      sample_endpoints = endpoints.sample([5, endpoints.size].min)
      
      # Calculate the average 95th percentile across these endpoints
      total_p95 = sample_endpoints.sum do |endpoint|
        # Get the 95th percentile response time
        count = redis.zcard(endpoint)
        next 0 if count == 0
        
        p95_index = (count * 0.95).ceil - 1
        p95_index = 0 if p95_index < 0
        
        # Get the score at the 95th percentile
        element = redis.zrange(endpoint, p95_index, p95_index, with_scores: true)
        element.any? ? element[0][1] : 0
      end
      
      sample_endpoints.size > 0 ? (total_p95 / sample_endpoints.size).round(2) : 0
    end
    
    def determine_health_status(error_rate, avg_response_time, order_success_rate)
      if error_rate > 5 || avg_response_time > 1000 || order_success_rate < 95
        'critical'
      elsif error_rate > 2 || avg_response_time > 500 || order_success_rate < 98
        'warning'
      else
        'healthy'
      end
    end
  end
end
