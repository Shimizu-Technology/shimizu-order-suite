# app/middleware/tenant_metrics_middleware.rb
#
# The TenantMetricsMiddleware captures metrics about API requests for each tenant.
# It measures request duration, tracks error rates, and logs tenant-specific
# request data for analytics purposes.
#
class TenantMetricsMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    # Skip metrics collection for certain paths
    return @app.call(env) if skip_path?(env['PATH_INFO'])
    
    # Start timing the request
    start_time = Time.now
    
    # Process the request
    status, headers, response = @app.call(env)
    
    # Calculate request duration in milliseconds
    duration = ((Time.now - start_time) * 1000).round(2)
    
    # Attempt to identify the tenant from the request
    restaurant = identify_tenant(env)
    
    # Track metrics if we have a tenant
    if restaurant
      track_request_metrics(env, status, duration, restaurant)
    end
    
    # Return the original response
    [status, headers, response]
  rescue => e
    # Log the error but don't interfere with the request
    Rails.logger.error("Error in TenantMetricsMiddleware: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    
    # Let the request continue
    @app.call(env)
  end
  
  private
  
  def skip_path?(path)
    # Skip metrics for assets, health checks, etc.
    path.start_with?('/assets/', '/health/', '/cable', '/favicon.ico') ||
      path == '/'
  end
  
  def identify_tenant(env)
    # Try to extract tenant from the request
    request = ActionDispatch::Request.new(env)
    
    # First check if we have a current_restaurant in thread local
    return ActiveRecord::Base.current_restaurant if ActiveRecord::Base.current_restaurant
    
    # Then try to get it from the controller
    controller = env['action_controller.instance']
    return controller.instance_variable_get('@current_restaurant') if controller
    
    # Try to get from JWT token
    token = extract_token(request)
    if token
      begin
        payload = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')[0]
        restaurant_id = payload['restaurant_id']
        return Restaurant.find_by(id: restaurant_id) if restaurant_id
      rescue JWT::DecodeError
        # Invalid token, continue with other methods
      end
    end
    
    # Try to get from params
    restaurant_id = request.params['restaurant_id']
    return Restaurant.find_by(id: restaurant_id) if restaurant_id
    
    # No tenant identified
    nil
  end
  
  def extract_token(request)
    auth_header = request.headers['Authorization']
    return nil unless auth_header
    
    # Extract the token from the Authorization header
    auth_header.split(' ').last
  end
  
  def track_request_metrics(env, status, duration, restaurant)
    request = ActionDispatch::Request.new(env)
    
    # Extract controller and action
    controller = env['action_controller.instance']
    if controller
      controller_name = controller.class.name
      action_name = env['action_dispatch.request.path_parameters'][:action]
    else
      # If we can't get the controller instance, use the path
      controller_name = 'Unknown'
      action_name = request.path
    end
    
    # Track the API request
    TenantMetricsService.track_api_request(
      restaurant,
      controller_name,
      action_name,
      duration
    )
    
    # If this is an error response, track it
    if status >= 400
      TenantMetricsService.track_error(
        restaurant,
        "http_#{status}",
        {
          path: request.path,
          method: request.method,
          controller: controller_name,
          action: action_name
        }
      )
    end
    
    # Log the request for analytics if it's not a GET request or it's an error
    if request.method != 'GET' || status >= 400
      # Try to identify the user
      user_id = nil
      if controller && controller.respond_to?(:current_user) && controller.current_user
        user_id = controller.current_user.id
      end
      
      # Log the event
      TenantEvent.log_api_request(
        restaurant,
        controller_name,
        action_name,
        duration,
        status,
        user_id
      )
    end
  end
end
