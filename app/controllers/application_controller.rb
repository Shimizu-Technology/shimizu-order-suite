# app/controllers/application_controller.rb

class ApplicationController < ActionController::API
  include TenantIsolation
  include Pundit::Authorization
  
  # Add around_action to track controller actions
  around_action :track_request, unless: :skip_tracking?
  
  # Rescue from Pundit authorization errors
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  def authorize_request
    header = request.headers["Authorization"]
    token = header.split(" ").last if header

    begin
      # Use TokenService to verify and decode the token
      decoded = TokenService.verify_token(token)
      @current_user = User.find(decoded["user_id"])
      
      # IMPORTANT: The tenant context is already set in the before_action :set_current_tenant callback
      # from the TenantIsolation concern, which runs before this method
      # This ensures that the restaurant_id from the request parameters or headers takes precedence
      
      # If we don't have a tenant context yet, try to use the one from the token
      if !@current_restaurant && !ActiveRecord::Base.current_restaurant
        restaurant_id = decoded["restaurant_id"]
        if restaurant_id.present?
          @current_restaurant = Restaurant.find_by(id: restaurant_id)
          
          # Verify user still belongs to this restaurant
          unless @current_user.super_admin? || @current_user.restaurant_id == @current_restaurant&.id
            render json: { errors: "User not authorized for this restaurant" }, status: :forbidden
            return nil
          end
          
          # Set tenant context only if it wasn't already set
          set_tenant_context(@current_restaurant)
        elsif !global_access_permitted?
          render json: { errors: "Restaurant context required" }, status: :unprocessable_entity
          return nil
        end
      end
    rescue TokenService::TokenRevokedError
      render json: { errors: "Token has been revoked" }, status: :unauthorized
    rescue ActiveRecord::RecordNotFound, JWT::DecodeError => e
      Rails.logger.error("JWT Authorization error: #{e.message}")
      render json: { errors: "Unauthorized" }, status: :unauthorized
    end
  end

  def current_user
    @current_user
  end

  # optional_authorize tries to decode the token if present but doesn't fail if invalid
  def optional_authorize
    header = request.headers["Authorization"]
    token = header.split(" ").last if header
    return unless token  # no token => do nothing => user remains nil

    begin
      # Use TokenService to verify and decode the token
      decoded = TokenService.verify_token(token)
      @current_user = User.find(decoded["user_id"])
      
      # IMPORTANT: Do not override the tenant context that was already set by the TenantIsolation concern
      # This ensures that the restaurant_id from the request parameters or headers takes precedence
      # over the one in the token, especially for super_admin users
      #
      # The tenant context is already set in the before_action :set_current_tenant callback
      # from the TenantIsolation concern, which runs before this method
    rescue TokenService::TokenRevokedError, ActiveRecord::RecordNotFound, JWT::DecodeError => e
      # Log the error but don't fail the request
      Rails.logger.debug("Optional JWT authorization failed: #{e.message}")
      # do nothing => user stays nil
    end
  end

  def is_admin?
    current_user && current_user.admin_or_above?
  end
  
  def require_admin!
    unless current_user && current_user.admin_or_above?
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end
  
  def require_admin_or_staff
    unless current_user && (current_user.admin_or_above? || current_user.staff?)
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end
  
  private
  
  def user_not_authorized
    render json: { error: "You are not authorized to perform this action" }, status: :forbidden
  end
  
  private
  
  def analytics
    @analytics ||= AnalyticsService.new(current_user, @current_restaurant)
  end
  
  def track_request
    start_time = Time.current
    yield
    duration = (Time.current - start_time) * 1000
    
    # Skip tracking for specific actions/controllers
    return if skip_tracking?
    
    # Track controller action as an event
    analytics.track("controller.#{controller_name}.#{action_name}", {
      status: response.status,
      duration_ms: duration.to_i,
      params: filtered_params # Define this to exclude sensitive params
    })
  end
  
  def filtered_params
    # Return a filtered version of params that excludes sensitive information
    params.to_unsafe_h.except('password', 'token', 'auth_token', 'credit_card')
  end
  
  def skip_tracking?
    controller_name == 'health' || # Skip health checks
    (controller_name == 'sessions' && action_name == 'create') # Skip login attempts
  end
end
