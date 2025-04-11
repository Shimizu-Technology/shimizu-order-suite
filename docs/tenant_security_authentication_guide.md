# Phase 5: Authentication and Authorization for Multi-Tenancy

This document describes the implementation of tenant-aware authentication and authorization in the Shimizu Order Suite multi-tenant architecture. These security measures ensure that users can only access data and functionality appropriate for their tenant.

## Overview

The tenant-aware authentication and authorization system implements the following key principles:

1. **Tenant-Specific User Authentication**: Users are associated with specific tenants
2. **Role-Based Access Control**: Permissions are scoped to tenant boundaries
3. **Super Admin Capabilities**: Special handling for cross-tenant administrative access
4. **Tenant Validation Middleware**: Request-level tenant validation

## Implementation Details

### User-Tenant Association

Users are associated with specific tenants through the `restaurant_id` field:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  belongs_to :restaurant, optional: true
  
  # Super admins don't belong to a specific tenant
  validates :restaurant_id, presence: true, unless: :super_admin?
  
  # User roles
  enum role: { customer: 0, staff: 1, manager: 2, admin: 3, super_admin: 4 }
  
  # Check if user belongs to a specific tenant
  def belongs_to_tenant?(restaurant_id)
    super_admin? || self.restaurant_id == restaurant_id
  end
end
```

### Authentication Flow

The authentication flow includes tenant validation:

```ruby
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  def create
    user = User.find_by(email: params[:email])
    
    if user&.authenticate(params[:password])
      # Set tenant context
      Current.user = user
      Current.restaurant_id = user.restaurant_id unless user.super_admin?
      
      # Log successful authentication
      AuditLog.log_authentication(user, 'login_success', request.remote_ip)
      
      # Generate JWT token with tenant information
      token = generate_jwt_token(user)
      
      render json: { token: token }
    else
      # Log failed authentication
      AuditLog.log_authentication_failure(params[:email], 'invalid_credentials', request.remote_ip)
      
      render json: { error: "Invalid credentials" }, status: :unauthorized
    end
  end
  
  private
  
  def generate_jwt_token(user)
    payload = {
      user_id: user.id,
      restaurant_id: user.restaurant_id,
      role: user.role,
      exp: 24.hours.from_now.to_i
    }
    
    JWT.encode(payload, Rails.application.credentials.secret_key_base)
  end
end
```

### Tenant Validation Middleware

The `TenantValidationMiddleware` validates tenant access for each request:

```ruby
# app/middleware/tenant_validation_middleware.rb
class TenantValidationMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    request = ActionDispatch::Request.new(env)
    
    # Skip validation for public endpoints
    return @app.call(env) if public_endpoint?(request)
    
    # Extract tenant ID from request
    tenant_id = extract_tenant_id(request)
    
    # Extract user from request
    current_user = extract_current_user(request)
    
    # Validate tenant access
    if tenant_id.present? && current_user.present?
      unless current_user.super_admin? || current_user.restaurant_id == tenant_id
        # Log unauthorized access attempt
        AuditLog.log_security_event(
          current_user,
          'unauthorized_tenant_access',
          'Restaurant',
          tenant_id,
          request.remote_ip,
          { attempted_restaurant_id: tenant_id, user_restaurant_id: current_user.restaurant_id }
        )
        
        # Return unauthorized response
        return [403, { 'Content-Type' => 'application/json' }, [{ error: 'Unauthorized tenant access' }.to_json]]
      end
    end
    
    # Set tenant context for the request
    Current.restaurant_id = tenant_id if tenant_id.present?
    Current.user = current_user if current_user.present?
    
    # Process the request
    @app.call(env)
  ensure
    # Clear tenant context after request
    Current.reset
  end
  
  private
  
  def public_endpoint?(request)
    # List of endpoints that don't require tenant validation
    public_paths = [
      '/api/v1/login',
      '/api/v1/signup',
      '/api/v1/restaurants/public'
    ]
    
    public_paths.any? { |path| request.path.start_with?(path) }
  end
  
  def extract_tenant_id(request)
    # Extract from URL parameter
    tenant_id = request.params['restaurant_id']
    
    # Extract from request headers
    tenant_id ||= request.headers['X-Restaurant-ID']
    
    # Convert to integer if present
    tenant_id.to_i if tenant_id.present?
  end
  
  def extract_current_user(request)
    # Extract JWT token from Authorization header
    auth_header = request.headers['Authorization']
    return nil unless auth_header.present? && auth_header.start_with?('Bearer ')
    
    token = auth_header.split(' ').last
    
    begin
      # Decode the token
      decoded_token = JWT.decode(token, Rails.application.credentials.secret_key_base, true, algorithm: 'HS256')
      payload = decoded_token.first
      
      # Find the user
      User.find_by(id: payload['user_id'])
    rescue JWT::DecodeError
      nil
    end
  end
end
```

### Authorization with Pundit Policies

Tenant-aware authorization is implemented using Pundit policies:

```ruby
# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  # Basic authorization methods
  def show?
    user_belongs_to_same_tenant_as_record?
  end

  def create?
    user_belongs_to_same_tenant_as_record?
  end

  def update?
    user_belongs_to_same_tenant_as_record?
  end

  def destroy?
    user_belongs_to_same_tenant_as_record?
  end

  protected

  def user_belongs_to_same_tenant_as_record?
    return true if user.super_admin?
    return false unless user.present?
    
    if record.respond_to?(:restaurant_id)
      user.restaurant_id == record.restaurant_id
    else
      false
    end
  end
end
```

### Super Admin Capabilities

Super admins have special capabilities for cross-tenant administration:

```ruby
# app/controllers/admin/restaurants_controller.rb
class Admin::RestaurantsController < ApplicationController
  before_action :authorize_super_admin
  
  def index
    @restaurants = Restaurant.unscoped.all
    render json: @restaurants
  end
  
  def show
    @restaurant = Restaurant.unscoped.find(params[:id])
    
    # Temporarily switch tenant context for the request
    Current.restaurant_id = @restaurant.id
    
    # Get restaurant-specific data
    @stats = collect_restaurant_stats
    
    render json: { restaurant: @restaurant, stats: @stats }
  end
  
  private
  
  def authorize_super_admin
    unless current_user&.super_admin?
      render json: { error: "Unauthorized" }, status: :forbidden
    end
  end
  
  def collect_restaurant_stats
    # This will use the Current.restaurant_id set above
    {
      orders_count: Order.count,
      revenue: Order.sum(:total_amount),
      customers_count: Customer.count
    }
  end
end
```

## Rate Limiting and Brute Force Protection

Tenant-aware rate limiting protects against brute force attacks:

```ruby
# app/middleware/tenant_rate_limiting_middleware.rb
class TenantRateLimitingMiddleware
  def initialize(app)
    @app = app
    @redis = Redis.new(url: ENV['REDIS_URL'])
    @max_requests = ENV.fetch('MAX_REQUESTS_PER_MINUTE', 60).to_i
    @window_seconds = ENV.fetch('RATE_LIMIT_WINDOW_SECONDS', 60).to_i
  end
  
  def call(env)
    request = ActionDispatch::Request.new(env)
    
    # Skip rate limiting for certain paths
    return @app.call(env) if excluded_path?(request.path)
    
    # Get client IP
    client_ip = request.remote_ip
    
    # Get tenant ID if available
    tenant_id = extract_tenant_id(request)
    
    # Create rate limit key based on IP and tenant
    rate_limit_key = tenant_id.present? ? "rate_limit:#{client_ip}:#{tenant_id}" : "rate_limit:#{client_ip}"
    
    # Check if rate limited
    if rate_limited?(rate_limit_key)
      # Log rate limit exceeded
      AuditLog.log_security_event(
        nil,
        'rate_limit_exceeded',
        'Request',
        nil,
        client_ip,
        { tenant_id: tenant_id, path: request.path }
      )
      
      # Return rate limit exceeded response
      return [429, { 'Content-Type' => 'application/json' }, [{ error: 'Rate limit exceeded' }.to_json]]
    end
    
    # Process the request
    @app.call(env)
  end
  
  private
  
  def excluded_path?(path)
    # List of paths excluded from rate limiting
    excluded_paths = [
      '/health',
      '/metrics'
    ]
    
    excluded_paths.any? { |excluded| path.start_with?(excluded) }
  end
  
  def extract_tenant_id(request)
    # Extract from URL parameter
    tenant_id = request.params['restaurant_id']
    
    # Extract from request headers
    tenant_id ||= request.headers['X-Restaurant-ID']
    
    # Convert to integer if present
    tenant_id.to_i if tenant_id.present?
  end
  
  def rate_limited?(key)
    # Increment the counter
    count = @redis.incr(key)
    
    # Set expiration if this is the first request in the window
    @redis.expire(key, @window_seconds) if count == 1
    
    # Check if rate limited
    count > @max_requests
  end
end
```

## Testing Strategy

Authentication and authorization are tested with:

1. **Unit Tests**: Verifying policy behavior
2. **Integration Tests**: Ensuring proper tenant validation
3. **Security Tests**: Attempting to bypass tenant boundaries

Example test:

```ruby
# Test tenant validation middleware
test "prevents access to other tenant's data" do
  # Create user for restaurant1
  user = users(:restaurant1_user)
  
  # Generate token for the user
  token = generate_token_for(user)
  
  # Attempt to access restaurant2's data
  get "/api/v1/restaurants/#{restaurants(:restaurant2).id}/menu_items",
      headers: { 'Authorization' => "Bearer #{token}" }
  
  # Verify access is denied
  assert_response :forbidden
  assert_equal({ 'error' => 'Unauthorized tenant access' }, JSON.parse(response.body))
end
```

## Security Considerations

1. **JWT Token Security**: Tokens include tenant information and are signed
2. **Audit Logging**: All authentication and authorization events are logged
3. **Rate Limiting**: Prevents brute force attacks against tenant endpoints
4. **Super Admin Restrictions**: Super admin capabilities are carefully controlled

## Best Practices

When implementing tenant-aware authentication and authorization:

1. Always associate users with tenants
2. Include tenant validation in the authentication flow
3. Implement tenant-aware policies for authorization
4. Use middleware for request-level tenant validation
5. Implement rate limiting with tenant awareness
6. Log all security events for audit purposes

## Conclusion

Tenant-aware authentication and authorization ensure that users can only access data and functionality appropriate for their tenant. By implementing multiple layers of security, including user-tenant association, middleware validation, and policy-based authorization, we maintain strong tenant boundaries throughout the application.
