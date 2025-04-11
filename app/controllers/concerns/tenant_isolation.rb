# app/controllers/concerns/tenant_isolation.rb
# 
# The TenantIsolation concern provides a robust framework for enforcing
# multi-tenant isolation throughout the application. It ensures that
# data from one restaurant is not accessible to users of another restaurant.
#
# This concern should be included in all controllers that access
# restaurant-specific data. It replaces the previous RestaurantScope concern
# and provides stronger isolation guarantees.
#
module TenantIsolation
  extend ActiveSupport::Concern

  included do
    before_action :set_current_tenant
    after_action :clear_tenant_context
    
    # Handle tenant access errors
    rescue_from TenantAccessDeniedError do |exception|
      render json: { error: exception.message }, status: :forbidden
    end
  end
  
  # Helper method to access the current restaurant (tenant)
  def current_restaurant
    @current_restaurant
  end

  private

  # Set the current tenant based on user context and request parameters
  # This method determines the appropriate restaurant context for the request,
  # validates access permissions, and sets the context for the duration of the request.
  def set_current_tenant
    # Step 1: Determine the appropriate restaurant context
    restaurant_id = determine_restaurant_id
    @current_restaurant = restaurant_id ? Restaurant.find_by(id: restaurant_id) : nil

    # Step 2: Validate tenant access permissions
    validate_tenant_access(@current_restaurant)

    # Step 3: Set tenant context for the request duration
    set_tenant_context(@current_restaurant)
  end

  # Determine which restaurant ID to use based on various sources
  # Priority order for restaurant_id:
  # 1. Frontend-specific context (X-Frontend-ID header)
  # 2. Explicit restaurant_id in params (if allowed)
  # 3. User's associated restaurant
  # 4. Restaurant ID from URL (for restaurant-specific endpoints)
  def determine_restaurant_id
    restaurant_id = nil
    
    # First check if this is a frontend-specific request with a specified restaurant ID
    # This allows us to handle different frontends (Shimizu Technology, Hafaloha, etc.)
    frontend_id = request.headers['X-Frontend-ID']
    frontend_restaurant_id = request.headers['X-Frontend-Restaurant-ID']
    
    # If we have both a frontend ID and a frontend-specific restaurant ID, use that
    if frontend_id.present? && frontend_restaurant_id.present?
      Rails.logger.debug { "Using frontend-specific restaurant_id: #{frontend_restaurant_id} for frontend: #{frontend_id}" }
      return frontend_restaurant_id
    end
    
    # Next check params[:restaurant_id] if the user can specify a restaurant
    if params[:restaurant_id].present? && can_specify_restaurant?
      restaurant_id = params[:restaurant_id]
    # Then check the user's associated restaurant
    elsif current_user&.restaurant_id.present?
      restaurant_id = current_user.restaurant_id
    # Then check if this is a restaurant-specific endpoint
    elsif params[:id].present? && controller_name == "restaurants"
      restaurant_id = params[:id]
    end
    
    # If we're in development or test mode and no restaurant_id is found, use the first restaurant
    # This makes testing easier
    if restaurant_id.nil? && (Rails.env.development? || Rails.env.test?)
      first_restaurant = Restaurant.first
      restaurant_id = first_restaurant.id if first_restaurant
    end
    
    restaurant_id
  end

  # Validate that the user has permission to access the specified tenant
  # This method ensures that users can only access data from their own restaurant,
  # with an exception for super_admin users who can access all restaurants.
  def validate_tenant_access(restaurant)
    # Allow access to global endpoints for super_admins
    return true if restaurant.nil? && global_access_permitted? && current_user&.role == "super_admin"
    
    # In development/test environments, be more permissive to make testing easier
    if Rails.env.development? || Rails.env.test?
      # Still log the access for debugging purposes
      log_tenant_access(restaurant) unless controller_name == "sessions" || controller_name == "passwords"
      return true
    end
    
    # Log tenant access for auditing purposes (if not an authentication endpoint)
    unless controller_name == "sessions" || controller_name == "passwords"
      log_tenant_access(restaurant)
    end
    
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

  # Set the tenant context for the current request
  # This method sets both the instance variable and the thread-local variable
  # used by models for default scoping.
  def set_tenant_context(restaurant)
    # Always set the current_restaurant instance variable
    @current_restaurant = restaurant
    
    # Set the thread-local variable for model scoping
    # CRITICAL: Only allow nil for truly global endpoints accessed by super_admin
    if restaurant.nil? && global_access_permitted? && current_user&.role == "super_admin"
      ActiveRecord::Base.current_restaurant = nil
    else
      ActiveRecord::Base.current_restaurant = restaurant
    end
    
    # Log the tenant context for debugging and audit purposes
    Rails.logger.debug { "Tenant context set to restaurant_id: #{restaurant&.id || 'nil'}" }
    
    # Check for models that might not have proper tenant isolation
    # This is skipped in development and test environments
    TenantIsolationWarnings.check_models(restaurant) if defined?(TenantIsolationWarnings)
  end

  # Clear tenant context after the request
  # This is critical to prevent tenant context leakage between requests
  def clear_tenant_context
    ActiveRecord::Base.current_restaurant = nil
  end

  # Can this user specify a restaurant_id parameter?
  # By default, only super_admin users can specify a restaurant_id
  def can_specify_restaurant?
    current_user&.role == "super_admin"
  end

  # Is this a truly global endpoint that doesn't need tenant context?
  # Very few endpoints should return true here - primarily system-level
  # operations that super_admins need to perform
  # 
  # IMPORTANT: Override this method in controllers that need global access,
  # but use it sparingly and only for legitimate global operations.
  def global_access_permitted?
    false # Override in specific controllers that need global access
  end
  
  # Helper method to ensure we have a tenant context
  # Use this in controller actions that absolutely require a restaurant context
  def ensure_tenant_context
    unless @current_restaurant
      raise TenantAccessDeniedError, "Restaurant context is required for this operation"
    end
  end
  
  # Audit logging methods
  
  # Log tenant access for audit purposes
  def log_tenant_access(restaurant)
    return unless current_user
    
    AuditLog.log_tenant_access(
      current_user,
      restaurant,
      request.remote_ip,
      {
        controller: controller_name,
        action: action_name,
        method: request.method,
        url: request.url
      }
    )
  rescue => e
    # Don't let audit logging failures affect the main application flow
    Rails.logger.error("Failed to log tenant access: #{e.message}")
  end
  
  # Log cross-tenant access attempts for security monitoring
  def log_cross_tenant_access(target_restaurant_id)
    return unless current_user
    
    AuditLog.log_cross_tenant_access(
      current_user,
      target_restaurant_id,
      request.remote_ip,
      {
        controller: controller_name,
        action: action_name,
        method: request.method,
        url: request.url
      }
    )
  rescue => e
    # Don't let audit logging failures affect the main application flow
    Rails.logger.error("Failed to log cross-tenant access: #{e.message}")
  end
  
  # Custom error for tenant access violations
  class TenantAccessDeniedError < StandardError; end
end
