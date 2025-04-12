# config/initializers/tenant_metrics_monitoring.rb
#
# This initializer sets up Prometheus metrics for tenant monitoring and analytics.
# It defines various counters, histograms, and gauges to track tenant-specific
# metrics for performance monitoring and business analytics.
#

require 'prometheus/client'

# Register the Prometheus metrics
prometheus = Prometheus::Client.registry

# Request metrics by tenant
tenant_request_counter = prometheus.counter(
  :tenant_request_total,
  docstring: 'Total number of HTTP requests by tenant',
  labels: [:restaurant_id, :controller, :action, :method, :status]
)

tenant_request_duration = prometheus.histogram(
  :tenant_request_duration_seconds,
  docstring: 'HTTP request duration in seconds by tenant',
  labels: [:restaurant_id, :controller, :action],
  buckets: [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
)

# Error metrics by tenant
tenant_error_counter = prometheus.counter(
  :tenant_error_total,
  docstring: 'Total number of errors by tenant',
  labels: [:restaurant_id, :error_type, :status]
)

# Cross-tenant access attempts
tenant_cross_access_counter = prometheus.counter(
  :tenant_cross_access_attempt_total,
  docstring: 'Total number of cross-tenant access attempts',
  labels: [:source_restaurant_id, :target_restaurant_id, :user_id, :controller, :action]
)

# Resource usage by tenant
tenant_resource_usage = prometheus.gauge(
  :tenant_resource_usage_count,
  docstring: 'Count of resources used by tenant',
  labels: [:restaurant_id, :resource]
)

# Daily active users by tenant
tenant_dau_gauge = prometheus.gauge(
  :tenant_daily_active_users,
  docstring: 'Daily active users by tenant',
  labels: [:restaurant_id]
)

# Monthly active users by tenant
tenant_mau_gauge = prometheus.gauge(
  :tenant_monthly_active_users,
  docstring: 'Monthly active users by tenant',
  labels: [:restaurant_id]
)

# Order metrics by tenant
tenant_order_counter = prometheus.counter(
  :tenant_order_total,
  docstring: 'Total number of orders by tenant',
  labels: [:restaurant_id, :payment_method, :status]
)

tenant_order_value_counter = prometheus.counter(
  :tenant_order_value_total,
  docstring: 'Total value of orders by tenant',
  labels: [:restaurant_id, :payment_method]
)

# Background job metrics by tenant
tenant_job_counter = prometheus.counter(
  :tenant_job_total,
  docstring: 'Total number of background jobs by tenant',
  labels: [:restaurant_id, :job_class, :status]
)

tenant_job_duration = prometheus.histogram(
  :tenant_job_duration_seconds,
  docstring: 'Background job duration in seconds by tenant',
  labels: [:restaurant_id, :job_class],
  buckets: [0.1, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300]
)

# Update resource usage metrics periodically
Thread.new do
  # Only run in production or when explicitly enabled
  next unless Rails.env.production? || ENV['ENABLE_METRICS'] == 'true'
  
  loop do
    begin
      # Sleep for a while to avoid excessive DB queries
      sleep(ENV.fetch('METRICS_UPDATE_INTERVAL', 300).to_i)
      
      # Get the list of models with indirect tenant relationships
      indirect_tenant_models = Rails.application.config.indirect_tenant_models rescue []
      
      # Update resource usage metrics for each restaurant
      Restaurant.find_each do |restaurant|
        # Set the current restaurant context for models with indirect relationships
        ActiveRecord::Base.current_restaurant = restaurant
        
        # Count orders - using proper tenant isolation method
        begin
          order_count = if Order.column_names.include?("restaurant_id")
            Order.where(restaurant_id: restaurant.id).count
          elsif indirect_tenant_models.include?("Order")
            # Use the model's tenant scope method if it exists
            Order.respond_to?(:with_restaurant_scope) ? Order.with_restaurant_scope.count : Order.all.count
          else
            0
          end
          tenant_resource_usage.set(order_count, labels: { restaurant_id: restaurant.id, resource: 'orders' })
        rescue => e
          Rails.logger.error("Error counting orders for restaurant #{restaurant.id}: #{e.message}")
        end
        
        # Count users - using proper tenant isolation method
        begin
          user_count = if User.column_names.include?("restaurant_id")
            User.where(restaurant_id: restaurant.id).count
          elsif indirect_tenant_models.include?("User")
            User.respond_to?(:with_restaurant_scope) ? User.with_restaurant_scope.count : User.all.count
          else
            0
          end
          tenant_resource_usage.set(user_count, labels: { restaurant_id: restaurant.id, resource: 'users' })
        rescue => e
          Rails.logger.error("Error counting users for restaurant #{restaurant.id}: #{e.message}")
        end
        
        # Count menu items - using proper tenant isolation method
        begin
          menu_item_count = if MenuItem.column_names.include?("restaurant_id")
            MenuItem.where(restaurant_id: restaurant.id).count
          elsif indirect_tenant_models.include?("MenuItem")
            MenuItem.respond_to?(:with_restaurant_scope) ? MenuItem.with_restaurant_scope.count : MenuItem.all.count
          else
            0
          end
          tenant_resource_usage.set(menu_item_count, labels: { restaurant_id: restaurant.id, resource: 'menu_items' })
        rescue => e
          Rails.logger.error("Error counting menu items for restaurant #{restaurant.id}: #{e.message}")
        end
        
        # Count reservations - using proper tenant isolation method
        begin
          reservation_count = if Reservation.column_names.include?("restaurant_id")
            Reservation.where(restaurant_id: restaurant.id).count
          elsif indirect_tenant_models.include?("Reservation")
            Reservation.respond_to?(:with_restaurant_scope) ? Reservation.with_restaurant_scope.count : Reservation.all.count
          else
            0
          end
          tenant_resource_usage.set(reservation_count, labels: { restaurant_id: restaurant.id, resource: 'reservations' })
        rescue => e
          Rails.logger.error("Error counting reservations for restaurant #{restaurant.id}: #{e.message}")
        end
        
        # Update DAU/MAU metrics
        begin
          dau = TenantMetricsService.daily_active_users(restaurant)
          mau = TenantMetricsService.monthly_active_users(restaurant)
          
          tenant_dau_gauge.set(dau, labels: { restaurant_id: restaurant.id })
          tenant_mau_gauge.set(mau, labels: { restaurant_id: restaurant.id })
        rescue => e
          Rails.logger.error("Error updating DAU/MAU metrics for restaurant #{restaurant.id}: #{e.message}")
        end
        
        # Clear the tenant context after processing this restaurant
        ActiveRecord::Base.current_restaurant = nil
      end
    rescue => e
      # Log error but don't crash the thread
      Rails.logger.error("Error updating tenant metrics: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end
end

# Instrument ActionController for request metrics
ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload
  
  # Skip if we don't have a restaurant_id
  next unless payload[:restaurant_id].present?
  
  # Extract request details
  controller = payload[:controller]
  action = payload[:action]
  method = payload[:method]
  status = payload[:status]
  duration = event.duration / 1000.0 # Convert from ms to seconds
  restaurant_id = payload[:restaurant_id]
  
  # Increment request counter
  tenant_request_counter.increment(
    labels: {
      restaurant_id: restaurant_id,
      controller: controller,
      action: action,
      method: method,
      status: status
    }
  )
  
  # Record request duration
  tenant_request_duration.observe(
    duration,
    labels: {
      restaurant_id: restaurant_id,
      controller: controller,
      action: action
    }
  )
  
  # Track errors (status >= 400)
  if status.to_i >= 400
    tenant_error_counter.increment(
      labels: {
        restaurant_id: restaurant_id,
        error_type: "http_#{status}",
        status: status
      }
    )
  end
end

# Instrument ActiveJob for background job metrics
ActiveSupport::Notifications.subscribe('perform.active_job') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload
  
  # Extract job details
  job = payload[:job]
  job_class = job.class.name
  
  # Try to determine restaurant_id from various sources
  restaurant_id = nil
  
  # First check if the job has a restaurant_id method
  restaurant_id = job.restaurant_id if job.respond_to?(:restaurant_id) && job.restaurant_id.present?
  
  # Next check if the first argument is an ActiveRecord object with restaurant_id
  if restaurant_id.nil? && job.arguments.first.is_a?(ActiveRecord::Base)
    if job.arguments.first.respond_to?(:restaurant_id) && job.arguments.first.restaurant_id.present?
      restaurant_id = job.arguments.first.restaurant_id
    elsif job.arguments.first.respond_to?(:restaurant) && job.arguments.first.restaurant.present?
      restaurant_id = job.arguments.first.restaurant.id
    end
  end
  
  # Check if the first argument is a Hash with restaurant_id
  restaurant_id ||= job.arguments.first[:restaurant_id] if job.arguments.first.is_a?(Hash) && job.arguments.first[:restaurant_id]
  
  # Skip if we still don't have a restaurant_id
  next unless restaurant_id.present?
  
  # Calculate duration
  duration = event.duration / 1000.0 # Convert from ms to seconds
  
  # Determine job status
  status = payload[:exception] ? 'failed' : 'completed'
  
  # Increment job counter
  tenant_job_counter.increment(
    labels: {
      restaurant_id: restaurant_id,
      job_class: job_class,
      status: status
    }
  )
  
  # Record job duration
  tenant_job_duration.observe(
    duration,
    labels: {
      restaurant_id: restaurant_id,
      job_class: job_class
    }
  )
end

# Instrument cross-tenant access attempts
ActiveSupport::Notifications.subscribe('tenant.cross_access_attempt') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload
  
  # Increment cross-tenant access counter
  tenant_cross_access_counter.increment(
    labels: {
      source_restaurant_id: payload[:source_restaurant_id],
      target_restaurant_id: payload[:target_restaurant_id],
      user_id: payload[:user_id],
      controller: payload[:controller],
      action: payload[:action]
    }
  )
end

# Instrument order creation for order metrics
ActiveSupport::Notifications.subscribe('order.created') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload
  
  order = payload[:order]
  restaurant_id = order.restaurant_id
  payment_method = order.payment_method || 'unknown'
  status = order.status
  
  # Increment order counter
  tenant_order_counter.increment(
    labels: {
      restaurant_id: restaurant_id,
      payment_method: payment_method,
      status: status
    }
  )
  
  # Increment order value counter
  tenant_order_value_counter.increment(
    by: order.total_amount.to_f,
    labels: {
      restaurant_id: restaurant_id,
      payment_method: payment_method
    }
  )
end
