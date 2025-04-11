# app/middleware/tenant_validation_middleware.rb
#
# The TenantValidationMiddleware is responsible for validating tenant context
# for all incoming requests. It ensures that:
#
# 1. All authenticated requests have a valid tenant context
# 2. Requests with invalid tenant context are rejected
# 3. Rate limiting is applied on a per-tenant basis
#
# This middleware works in conjunction with the TenantIsolation concern
# to provide a robust multi-tenant security framework.
#
class TenantValidationMiddleware
  # Initialize the middleware with the app and options
  # @param app [Object] The Rack application
  # @param options [Hash] Configuration options
  def initialize(app, options = {})
    @app = app
    @options = options
    @rate_limit_store = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
    @rate_limit_window = options[:rate_limit_window] || 60 # seconds
    @rate_limit_max_requests = options[:rate_limit_max_requests] || 100 # requests per window
  end

  # Process the request
  # @param env [Hash] The Rack environment
  # @return [Array] The Rack response
  def call(env)
    request = ActionDispatch::Request.new(env)
    
    # Skip validation for public endpoints
    if public_endpoint?(request)
      return @app.call(env)
    end
    
    # Extract tenant context from the request
    tenant_id = extract_tenant_id(request)
    
    # Validate tenant context
    unless valid_tenant?(tenant_id, request)
      return invalid_tenant_response
    end
    
    # Apply rate limiting
    unless within_rate_limit?(tenant_id, request)
      return rate_limit_exceeded_response
    end
    
    # Process the request
    @app.call(env)
  rescue => e
    # Log the error
    Rails.logger.error("TenantValidationMiddleware error: #{e.message}")
    
    # Return a 500 error
    [500, { 'Content-Type' => 'application/json' }, [{ error: 'Internal server error' }.to_json]]
  end
  
  private
  
  # Check if the request is for a public endpoint
  # @param request [ActionDispatch::Request] The request
  # @return [Boolean] Whether the request is for a public endpoint
  def public_endpoint?(request)
    path = request.path
    
    # Static assets and public API endpoints
    public_paths = [
      '/health',
      '/api/v1/health',
      '/api/v1/restaurants/lookup',
      '/api/v1/sessions',
      '/api/v1/passwords'
    ]
    
    # Check if the path matches any public path
    public_paths.any? { |public_path| path.start_with?(public_path) } ||
      path.match?(/\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$/)
  end
  
  # Extract tenant ID from the request
  # @param request [ActionDispatch::Request] The request
  # @return [Integer, nil] The tenant ID or nil if not found
  def extract_tenant_id(request)
    # Try to extract from JWT token
    token = extract_token(request)
    if token
      begin
        decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')[0]
        return decoded['restaurant_id'] if decoded['restaurant_id'].present?
      rescue JWT::DecodeError
        # Token is invalid, continue with other methods
      end
    end
    
    # Try to extract from request parameters
    if request.params['restaurant_id'].present?
      return request.params['restaurant_id']
    end
    
    # Try to extract from URL path for restaurant-specific endpoints
    if request.path.match?(/\/api\/v1\/restaurants\/(\d+)/)
      return request.path.match(/\/api\/v1\/restaurants\/(\d+)/)[1]
    end
    
    # No tenant ID found
    nil
  end
  
  # Extract JWT token from the request
  # @param request [ActionDispatch::Request] The request
  # @return [String, nil] The token or nil if not found
  def extract_token(request)
    auth_header = request.headers['Authorization']
    return nil unless auth_header
    
    auth_header.split(' ').last
  end
  
  # Check if the tenant ID is valid
  # @param tenant_id [Integer, nil] The tenant ID
  # @param request [ActionDispatch::Request] The request
  # @return [Boolean] Whether the tenant ID is valid
  def valid_tenant?(tenant_id, request)
    # Public endpoints don't need tenant validation
    return true if public_endpoint?(request)
    
    # Skip validation for unauthenticated requests
    return true unless authenticated_request?(request)
    
    # Ensure tenant ID is present for authenticated requests
    return false unless tenant_id.present?
    
    # Check if the tenant exists
    Restaurant.exists?(tenant_id)
  end
  
  # Check if the request is authenticated
  # @param request [ActionDispatch::Request] The request
  # @return [Boolean] Whether the request is authenticated
  def authenticated_request?(request)
    request.headers['Authorization'].present?
  end
  
  # Check if the request is within rate limits
  # @param tenant_id [Integer, nil] The tenant ID
  # @param request [ActionDispatch::Request] The request
  # @return [Boolean] Whether the request is within rate limits
  def within_rate_limit?(tenant_id, request)
    # Skip rate limiting for unauthenticated requests
    return true unless authenticated_request?(request)
    
    # Skip rate limiting if no tenant ID is present
    return true unless tenant_id.present?
    
    # Generate a rate limit key for this tenant
    key = "rate_limit:tenant:#{tenant_id}:#{Time.now.to_i / @rate_limit_window}"
    
    # Increment the counter
    count = @rate_limit_store.incr(key)
    
    # Set expiration if this is a new key
    if count == 1
      @rate_limit_store.expire(key, @rate_limit_window)
    end
    
    # Check if the count exceeds the limit
    count <= @rate_limit_max_requests
  end
  
  # Generate a response for invalid tenant
  # @return [Array] The Rack response
  def invalid_tenant_response
    [
      403,
      { 'Content-Type' => 'application/json' },
      [{ error: 'Invalid tenant context' }.to_json]
    ]
  end
  
  # Generate a response for rate limit exceeded
  # @return [Array] The Rack response
  def rate_limit_exceeded_response
    [
      429,
      { 'Content-Type' => 'application/json' },
      [{ error: 'Rate limit exceeded' }.to_json]
    ]
  end
end
