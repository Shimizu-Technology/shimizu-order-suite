# Multi-tenant Architecture

This document provides a comprehensive overview of Shimizu Order Suite's multi-tenant architecture, which allows the platform to serve multiple restaurants from a single codebase and database while maintaining strict data isolation.

## Overview

Shimizu Order Suite uses a multi-tenant architecture where all restaurants share the same database and application code, but data is isolated through application-level controls. This approach provides:

- **Efficient Resource Utilization**: Shared infrastructure reduces costs
- **Simplified Maintenance**: Single codebase for all tenants
- **Scalability**: Easy onboarding of new restaurants
- **Data Isolation**: Strong security boundaries between tenants

## Core Concepts

### Restaurant as Tenant

In Shimizu Order Suite, each restaurant represents a tenant. The `Restaurant` model is the central entity that:

1. Serves as the root for all tenant-specific data
2. Provides configuration settings for the tenant
3. Controls access to tenant-specific resources

```ruby
# app/models/restaurant.rb (simplified)
class Restaurant < ApplicationRecord
  has_many :users
  has_many :menus
  has_many :orders
  has_many :reservations
  has_many :merchandise_collections
  has_many :seat_sections
  has_many :vip_access_codes
  has_many :site_settings
  has_many :notification_templates
  
  attribute :allowed_origins, :string, array: true, default: []
  attribute :admin_settings, :jsonb, default: {}
  
  validates :name, presence: true
  validates :time_zone, presence: true
  
  # Current active menu and merchandise collection
  belongs_to :current_menu, class_name: 'Menu', optional: true
  belongs_to :current_merchandise_collection, class_name: 'MerchandiseCollection', optional: true
end
```

### Tenant Context

The tenant context is established and maintained throughout the request lifecycle:

1. **Authentication**: JWT tokens include the restaurant_id
2. **Context Setting**: The restaurant context is set at the beginning of each request
3. **Scoping**: All database queries are automatically scoped to the current restaurant
4. **Context Clearing**: The context is cleared at the end of each request

## Implementation Details

### Restaurant Scope Concern

The `RestaurantScope` concern is included in all controllers to establish the restaurant context:

```ruby
# app/controllers/concerns/restaurant_scope.rb
module RestaurantScope
  extend ActiveSupport::Concern
  
  included do
    before_action :set_restaurant_scope
    after_action :clear_restaurant_scope
  end
  
  private
  
  def set_restaurant_scope
    # For super_admin users who can access multiple restaurants
    if current_user&.role == 'super_admin'
      # Allow super_admin to specify which restaurant to work with
      @current_restaurant = if params[:restaurant_id].present?
                             Restaurant.find_by(id: params[:restaurant_id])
                           else
                             nil # Super admins can access global endpoints without restaurant context
                           end
    else
      # For regular users, always use their associated restaurant
      @current_restaurant = current_user&.restaurant
      
      # If no restaurant is associated and this isn't a public endpoint,
      # return an error
      unless @current_restaurant || public_endpoint?
        render json: { error: "Restaurant context required" }, status: :unprocessable_entity
        return
      end
    end
    
    # Make current_restaurant available to models for default scoping
    ActiveRecord::Base.current_restaurant = @current_restaurant
  end
  
  def clear_restaurant_scope
    ActiveRecord::Base.current_restaurant = nil
  end
  
  # Override this method in controllers that have public endpoints
  def public_endpoint?
    false
  end
end
```

### Thread-local Storage

The current restaurant is stored in thread-local storage to make it available throughout the request:

```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  
  # Thread-local storage for current restaurant
  thread_mattr_accessor :current_restaurant
  
  # Default scope method to be used by models
  def self.apply_default_scope
    default_scope { with_restaurant_scope }
  end
  
  # Default implementation of restaurant scoping
  def self.with_restaurant_scope
    if current_restaurant
      where(restaurant_id: current_restaurant.id)
    else
      all
    end
  end
end
```

### Model Scoping

All models that contain restaurant-specific data use default scoping to ensure data isolation:

```ruby
# Example model with default scoping
class Order < ApplicationRecord
  apply_default_scope
  belongs_to :restaurant
  
  # ... other associations and validations
end
```

For models that don't have a direct `restaurant_id` column but are associated with a restaurant through other models, custom scoping methods are implemented:

```ruby
# Example of indirect association scoping
class Option < ApplicationRecord
  belongs_to :option_group
  
  # Custom scoping method
  def self.with_restaurant_scope
    if current_restaurant
      joins(option_group: { menu_item: :menu })
        .where(menus: { restaurant_id: current_restaurant.id })
    else
      all
    end
  end
end
```

### Public Endpoints

Some endpoints need to be accessible without restaurant context (e.g., login, signup, public restaurant data). These override the `public_endpoint?` method:

```ruby
# Example of public endpoint in SessionsController
class SessionsController < ApplicationController
  # Override to allow public access to login and token refresh
  def public_endpoint?
    action_name.in?(['create', 'refresh'])
  end
  
  # POST /login
  def create
    # Login logic...
  end
  
  # POST /refresh_token
  def refresh
    # Token refresh logic...
  end
end
```

### Super Admin Access

Super admins can access data across multiple restaurants by specifying a `restaurant_id` parameter:

```ruby
# Example of super admin access in AdminController
class Admin::AnalyticsController < ApplicationController
  before_action :authorize_super_admin
  
  # GET /admin/analytics/sales
  def sales
    # If restaurant_id is provided, scope to that restaurant
    # Otherwise, include data from all restaurants
    @restaurant = params[:restaurant_id].present? ? 
                  Restaurant.find(params[:restaurant_id]) : 
                  nil
    
    if @restaurant
      @sales_data = Order.where(restaurant_id: @restaurant.id)
                         .group_by_day(:created_at)
                         .sum(:total_amount)
    else
      @sales_data = Order.group_by_day(:created_at)
                         .sum(:total_amount)
    end
    
    render json: @sales_data
  end
  
  private
  
  def authorize_super_admin
    unless current_user&.role == 'super_admin'
      render json: { error: "Unauthorized" }, status: :forbidden
    end
  end
end
```

### JWT Authentication with Restaurant Context

JWT tokens include the restaurant_id to maintain tenant context across requests. The TokenService handles token generation, verification, and revocation:

```ruby
# app/services/token_service.rb (simplified)
def self.generate_token(user, restaurant_id = nil, expiration = 24.hours.from_now)
  # Use provided restaurant_id or fall back to user's restaurant_id
  tenant_id = restaurant_id || user.restaurant_id
  
  # Create token payload
  payload = {
    user_id: user.id,
    restaurant_id: tenant_id,
    role: user.role,
    tenant_permissions: user_permissions(user, tenant_id),
    jti: SecureRandom.uuid, # JWT ID for revocation
    iat: Time.current.to_i, # Issued at time
    exp: expiration.to_i
  }
  
  # Encode the token
  JWT.encode(payload, Rails.application.secret_key_base)
end

# Token verification also validates tenant context
def self.verify_token(token)
  # Decode the token
  decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')[0]
  
  # Check if token has been revoked
  if token_revoked?(decoded["jti"])
    raise TokenRevokedError, "Token has been revoked"
  end
  
  # Return the decoded payload
  decoded
end
```

## Enhanced Security Features

### Tenant Isolation Concern

The `TenantIsolation` concern provides a robust framework for enforcing multi-tenant isolation throughout the application:

```ruby
# app/controllers/concerns/tenant_isolation.rb (simplified)
module TenantIsolation
  extend ActiveSupport::Concern

  included do
    before_action :set_current_tenant
    after_action :clear_tenant_context
  end

  private

  # Set the current tenant based on user context and request parameters
  def set_current_tenant
    # Step 1: Determine the appropriate restaurant context
    restaurant_id = determine_restaurant_id
    @current_restaurant = restaurant_id ? Restaurant.find_by(id: restaurant_id) : nil

    # Step 2: Validate tenant access permissions
    validate_tenant_access(@current_restaurant)

    # Step 3: Set tenant context for the request duration
    set_tenant_context(@current_restaurant)
  end
  
  # Validate that the user has permission to access the specified tenant
  def validate_tenant_access(restaurant)
    # Allow access to global endpoints for super_admins
    return true if restaurant.nil? && global_access_permitted? && current_user&.role == "super_admin"
    
    # Log tenant access for auditing purposes
    log_tenant_access(restaurant)
    
    # Allow super_admins to access any restaurant
    return true if current_user&.role == "super_admin"
    
    # Allow users to access their own restaurant
    return true if current_user&.restaurant_id == restaurant&.id
    
    # Special case for authentication endpoints
    return true if controller_name == "sessions" || controller_name == "passwords"
    
    # If we get here, the user is trying to access a restaurant they don't have permission for
    # Log cross-tenant access attempt for security monitoring
    log_cross_tenant_access(restaurant&.id)
    
    raise TenantAccessDeniedError, "You don't have permission to access this restaurant's data"
  end
end
```

### Audit Logging

Comprehensive audit logging tracks all tenant-related operations, particularly focusing on security-sensitive actions:

```ruby
# app/models/audit_log.rb (simplified)
class AuditLog < ApplicationRecord
  include TenantScoped
  
  # Associations
  belongs_to :user, optional: true
  
  # Validations
  validates :action, presence: true
  
  # Scopes
  scope :tenant_access_logs, -> { where(action: 'tenant_access') }
  scope :data_modification_logs, -> { where(action: %w[create update delete]) }
  scope :suspicious_activity, -> { where(action: 'suspicious_activity') }
  
  # Log tenant access
  def self.log_tenant_access(user, restaurant, ip_address, details = {})
    create(
      user_id: user&.id,
      restaurant_id: restaurant&.id,
      action: 'tenant_access',
      resource_type: 'Restaurant',
      resource_id: restaurant&.id,
      ip_address: ip_address,
      details: details
    )
  end
  
  # Log cross-tenant access attempt
  def self.log_cross_tenant_access(user, target_restaurant_id, ip_address, details = {})
    create(
      user_id: user&.id,
      restaurant_id: user&.restaurant_id,
      action: 'suspicious_activity',
      resource_type: 'Restaurant',
      resource_id: target_restaurant_id,
      ip_address: ip_address,
      details: details.merge({
        attempt_type: 'cross_tenant_access',
        user_restaurant_id: user&.restaurant_id,
        target_restaurant_id: target_restaurant_id
      })
    )
  end
end
```

### Tenant Validation Middleware

A dedicated middleware validates tenant context for all requests and implements rate limiting on a per-tenant basis:

```ruby
# app/middleware/tenant_validation_middleware.rb (simplified)
class TenantValidationMiddleware
  def initialize(app, options = {})
    @app = app
    @options = options
    @rate_limit_store = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
    @rate_limit_window = options[:rate_limit_window] || 60 # seconds
    @rate_limit_max_requests = options[:rate_limit_max_requests] || 100 # requests per window
  end

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
  end
end
```

### Dynamic CORS Configuration

Each restaurant can configure its own allowed frontend origins:

```ruby
# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins lambda { |source, env|
      request_origin = env["HTTP_ORIGIN"]
      
      # Check if origin is allowed for any restaurant
      Restaurant.where("allowed_origins @> ARRAY[?]::varchar[]", [request_origin]).exists? ||
      request_origin == 'http://localhost:5173' # Development exception
    }
    
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end
end
```

## Database Design

### Foreign Keys

All tenant-specific tables include a `restaurant_id` foreign key with a database-level constraint:

```ruby
# Example migration
class CreateOrders < ActiveRecord::Migration[7.0]
  def change
    create_table :orders do |t|
      t.references :restaurant, null: false, foreign_key: true
      # ... other columns
      t.timestamps
    end
    
    # Additional index for performance
    add_index :orders, [:restaurant_id, :status, :created_at]
  end
end
```

### Indexes

Composite indexes that include `restaurant_id` are used to optimize queries:

```ruby
# Example of performance indexes
class AddPerformanceIndexes < ActiveRecord::Migration[7.0]
  def change
    add_index :menu_items, [:restaurant_id, :category_id, :active], name: 'index_menu_items_on_restaurant_category_active'
    add_index :reservations, [:restaurant_id, :status, :reservation_time], name: 'index_reservations_on_restaurant_status_time'
    add_index :users, [:restaurant_id, :role], name: 'index_users_on_restaurant_role'
  end
end
```

## Testing

### Test Helpers

Test helpers are provided to set the restaurant context in tests:

```ruby
# spec/support/restaurant_context_helper.rb
module RestaurantContextHelper
  def with_restaurant(restaurant)
    old_restaurant = ActiveRecord::Base.current_restaurant
    ActiveRecord::Base.current_restaurant = restaurant
    yield
  ensure
    ActiveRecord::Base.current_restaurant = old_restaurant
  end
end

RSpec.configure do |config|
  config.include RestaurantContextHelper
end
```

### Example Tests

```ruby
# spec/models/order_spec.rb
RSpec.describe Order, type: :model do
  let(:restaurant1) { create(:restaurant) }
  let(:restaurant2) { create(:restaurant) }
  
  before do
    # Create orders for both restaurants
    create_list(:order, 3, restaurant: restaurant1)
    create_list(:order, 2, restaurant: restaurant2)
  end
  
  it "scopes queries to the current restaurant" do
    with_restaurant(restaurant1) do
      expect(Order.count).to eq(3)
    end
    
    with_restaurant(restaurant2) do
      expect(Order.count).to eq(2)
    end
  end
end
```

## Security Considerations

### Data Isolation

The multi-tenant architecture relies on application-level controls for data isolation. To ensure security:

1. **Default Scoping**: All models must use default scoping
2. **Manual Queries**: Raw SQL queries must include restaurant_id conditions
3. **Association Loading**: Eager loading must maintain tenant context
4. **Background Jobs**: Jobs must include restaurant context

### Potential Vulnerabilities

Be aware of these potential vulnerabilities:

1. **Missing Scopes**: Models without proper scoping could leak data
2. **N+1 Queries**: Inefficient queries might bypass scoping
3. **Raw SQL**: Unscoped SQL could access cross-tenant data
4. **Global Objects**: Singleton or global objects might mix tenant data

### Security Auditing

Regular security audits should check for:

1. **Models without Scoping**: Ensure all models have proper tenant scoping
2. **Unscoped Queries**: Look for queries that bypass the default scope
3. **Public Endpoints**: Verify that public endpoints don't leak sensitive data
4. **Super Admin Access**: Ensure super admin features have proper authorization

## Performance Considerations

### Query Optimization

Multi-tenant queries can be optimized by:

1. **Composite Indexes**: Include restaurant_id in composite indexes
2. **Eager Loading**: Use includes/joins to avoid N+1 queries
3. **Pagination**: Always paginate large result sets
4. **Caching**: Use per-tenant caching strategies

### Example of Optimized Query

```ruby
# Optimized query with eager loading and pagination
def index
  @orders = Order.includes(:user, :order_items)
                .where(status: params[:status]) if params[:status].present?
                .order(created_at: :desc)
                .page(params[:page])
                .per(params[:per_page] || 20)
  
  render json: {
    orders: @orders,
    total_pages: @orders.total_pages,
    current_page: @orders.current_page
  }
end
```

## Onboarding New Tenants

### Restaurant Creation

New restaurants are created through an admin interface or API:

```ruby
# Example of restaurant creation
def create
  @restaurant = Restaurant.new(restaurant_params)
  
  # Set default settings
  @restaurant.admin_settings = {
    notification_channels: {
      orders: { email: true, sms: true },
      reservations: { email: true, sms: false }
    },
    operating_hours: default_operating_hours
  }
  
  if @restaurant.save
    # Create default site settings
    SiteSetting.create!(restaurant: @restaurant)
    
    # Create admin user
    User.create!(
      email: params[:admin_email],
      password: SecureRandom.hex(8), # Temporary password
      role: 'admin',
      restaurant: @restaurant,
      require_password_change: true
    )
    
    render json: @restaurant, status: :created
  else
    render json: { errors: @restaurant.errors }, status: :unprocessable_entity
  end
end
```

### Data Migration

When migrating data from another system:

1. **Tenant Context**: Set the restaurant context during migration
2. **Transaction Safety**: Use transactions to ensure consistency
3. **Validation**: Validate imported data against model constraints

```ruby
# Example data migration
def import_data(restaurant, data_file)
  ActiveRecord::Base.transaction do
    # Set restaurant context
    ActiveRecord::Base.current_restaurant = restaurant
    
    # Parse data file
    data = JSON.parse(File.read(data_file))
    
    # Import menu items
    data['menu_items'].each do |item_data|
      menu_item = MenuItem.new(
        name: item_data['name'],
        description: item_data['description'],
        price: item_data['price'],
        category_id: find_or_create_category(item_data['category']).id,
        restaurant: restaurant
      )
      
      unless menu_item.save
        raise "Failed to import menu item: #{menu_item.errors.full_messages.join(', ')}"
      end
    end
    
    # Import other data...
  end
ensure
  # Clear restaurant context
  ActiveRecord::Base.current_restaurant = nil
end
```

## Best Practices

When working with the multi-tenant architecture, follow these best practices:

1. **Always Use Scoping**: Ensure all models have proper tenant scoping
2. **Test Data Isolation**: Write tests to verify tenant data isolation
3. **Include Restaurant in Associations**: Always include restaurant_id in associations
4. **Be Careful with Raw SQL**: Avoid raw SQL queries that might bypass scoping
5. **Clear Context After Use**: Always clear the restaurant context after setting it manually
6. **Use Transactions**: Wrap multi-step operations in transactions
7. **Validate Tenant Context**: Verify the tenant context is set before performing operations

## Troubleshooting

Common issues and their solutions:

1. **Data Leakage**: If data from one tenant is visible to another, check for missing scopes or incorrect joins
2. **Missing Data**: If expected data is not visible, verify the correct tenant context is set
3. **Performance Issues**: If queries are slow, check for missing indexes or inefficient joins
4. **Authentication Problems**: If JWT authentication fails, check that restaurant_id is included in the token
5. **CORS Issues**: If frontend requests are blocked, verify the restaurant's allowed_origins configuration

## Future Enhancements

Planned enhancements for the multi-tenant architecture:

1. **Tenant-specific Configurations**: More granular configuration options per tenant
2. **Shared Resources**: Support for resources shared across multiple tenants
3. **Tenant Groups**: Grouping of tenants for chain restaurants
4. **Tenant Analytics**: Cross-tenant analytics for super admins
5. **Tenant Isolation Improvements**: Enhanced security measures for tenant isolation
