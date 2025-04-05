# app/controllers/application_controller.rb

class ApplicationController < ActionController::API
  include RestaurantScope
  include Pundit::Authorization
  
  # Add around_action to track controller actions
  around_action :track_request, unless: :skip_tracking?
  
  # Rescue from Pundit authorization errors
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  def authorize_request
    header = request.headers["Authorization"]
    token = header.split(" ").last if header

    begin
      decoded = JWT.decode(token, Rails.application.secret_key_base)[0]
      @current_user = User.find(decoded["user_id"])

      # Check token expiration if exp is present
      if decoded["exp"].present? && Time.at(decoded["exp"]) < Time.current
        render json: { errors: "Token expired" }, status: :unauthorized
        nil
      end
    rescue ActiveRecord::RecordNotFound, JWT::DecodeError
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
      # Use the same decode logic & secret as authorize_request
      decoded = JWT.decode(token, Rails.application.secret_key_base)[0]
      @current_user = User.find(decoded["user_id"])

      # Check token expiration if exp is present
      nil if decoded["exp"].present? && Time.at(decoded["exp"]) < Time.current
    rescue ActiveRecord::RecordNotFound, JWT::DecodeError
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
