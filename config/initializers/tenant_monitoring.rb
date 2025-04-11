# config/initializers/tenant_monitoring.rb
#
# This initializer sets up monitoring for tenant isolation metrics.
# It tracks important metrics related to multi-tenant security and
# provides alerts for potential security issues.
#

# Only run in production or staging environments
if Rails.env.production? || Rails.env.staging?
  # Initialize monitoring client
  require 'prometheus/client'
  
  # Create a registry for our metrics
  TENANT_METRICS = Prometheus::Client.registry
  
  # Define metrics for tenant isolation monitoring
  
  # Counter for cross-tenant access attempts
  CROSS_TENANT_ACCESS_COUNTER = TENANT_METRICS.counter(
    :shimizu_cross_tenant_access_attempts_total,
    'Total number of cross-tenant access attempts',
    { restaurant_id: nil, user_id: nil }
  )
  
  # Counter for tenant access (normal operations)
  TENANT_ACCESS_COUNTER = TENANT_METRICS.counter(
    :shimizu_tenant_access_total,
    'Total number of tenant access operations',
    { restaurant_id: nil }
  )
  
  # Histogram for tenant request latency
  TENANT_REQUEST_LATENCY = TENANT_METRICS.histogram(
    :shimizu_tenant_request_latency_seconds,
    'Request latency by tenant',
    { restaurant_id: nil, controller: nil, action: nil },
    [0.01, 0.05, 0.1, 0.5, 1, 2, 5, 10]
  )
  
  # Gauge for active tenant sessions
  ACTIVE_TENANT_SESSIONS = TENANT_METRICS.gauge(
    :shimizu_active_tenant_sessions,
    'Number of active sessions by tenant',
    { restaurant_id: nil }
  )
  
  # Counter for rate limit exceeded events
  RATE_LIMIT_EXCEEDED_COUNTER = TENANT_METRICS.counter(
    :shimizu_rate_limit_exceeded_total,
    'Total number of rate limit exceeded events',
    { restaurant_id: nil }
  )
  
  # Subscribe to relevant ActiveSupport notifications
  
  # Monitor controller actions for tenant metrics
  ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    payload = event.payload
    
    # Skip if no current restaurant (public endpoint)
    next unless ActiveRecord::Base.current_restaurant
    
    # Record request latency
    TENANT_REQUEST_LATENCY.observe(
      event.duration / 1000.0,
      {
        restaurant_id: ActiveRecord::Base.current_restaurant.id.to_s,
        controller: payload[:controller],
        action: payload[:action]
      }
    )
    
    # Record tenant access
    TENANT_ACCESS_COUNTER.increment(
      { restaurant_id: ActiveRecord::Base.current_restaurant.id.to_s }
    )
  end
  
  # Setup hooks for AuditLog events
  
  # Hook into AuditLog for suspicious activity
  AuditLog.after_create do |audit_log|
    if audit_log.action == 'suspicious_activity'
      # Increment cross-tenant access counter
      CROSS_TENANT_ACCESS_COUNTER.increment(
        {
          restaurant_id: audit_log.restaurant_id.to_s,
          user_id: audit_log.user_id&.to_s || 'unknown'
        }
      )
      
      # Send alert for suspicious activity
      if Rails.env.production? && ENV['ALERT_WEBHOOK_URL'].present?
        RestClient.post(
          ENV['ALERT_WEBHOOK_URL'],
          {
            text: "🚨 SECURITY ALERT: Cross-tenant access attempt detected! " \
                  "User ID: #{audit_log.user_id}, " \
                  "Restaurant ID: #{audit_log.restaurant_id}, " \
                  "Target Restaurant ID: #{audit_log.details['target_restaurant_id']}, " \
                  "IP: #{audit_log.ip_address}"
          }.to_json,
          content_type: :json
        ) rescue nil # Don't let webhook failures affect application flow
      end
    end
  end
  
  # Hook into TenantValidationMiddleware for rate limit events
  module RateLimitMonitoring
    def rate_limit_exceeded_response
      # Increment rate limit counter
      if defined?(RATE_LIMIT_EXCEEDED_COUNTER) && @tenant_id
        RATE_LIMIT_EXCEEDED_COUNTER.increment(
          { restaurant_id: @tenant_id.to_s }
        )
      end
      
      # Call original method
      super
    end
  end
  
  # Apply the monitoring module to TenantValidationMiddleware
  TenantValidationMiddleware.prepend(RateLimitMonitoring)
  
  # Setup session tracking
  module SessionMonitoring
    def create
      result = super
      
      # Track new session
      if defined?(ACTIVE_TENANT_SESSIONS) && current_user&.restaurant_id
        ACTIVE_TENANT_SESSIONS.increment(
          { restaurant_id: current_user.restaurant_id.to_s }
        )
      end
      
      result
    end
    
    def destroy
      # Track session end
      if defined?(ACTIVE_TENANT_SESSIONS) && current_user&.restaurant_id
        ACTIVE_TENANT_SESSIONS.decrement(
          { restaurant_id: current_user.restaurant_id.to_s }
        )
      end
      
      super
    end
  end
  
  # Apply the monitoring module to SessionsController
  SessionsController.prepend(SessionMonitoring)
  
  # Log that monitoring is enabled
  Rails.logger.info "Tenant isolation monitoring enabled with #{TENANT_METRICS.metrics.size} metrics"
end
