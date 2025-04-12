# app/services/session_service.rb
class SessionService
  attr_reader :analytics
  
  def initialize(analytics_service = nil)
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Authenticate a user with email and password
  # @param email [String] User's email
  # @param password [String] User's password
  # @param restaurant_id [Integer] Optional restaurant_id for tenant-specific login
  def authenticate(email, password, restaurant_id = nil)
    begin
      # 1) We downcase the email => "john@EXAMPLE.com" => "john@example.com"
      # 2) Find by LOWER(email) = downcased email
      user = User.find_by(
        "LOWER(email) = ?",
        email.to_s.downcase
      )
      
      if user && user.authenticate(password)
        # For non-super_admin users, enforce restaurant-specific authentication
        if user.role != "super_admin" && restaurant_id.present?
          # If the user is trying to log in to a restaurant that's not their own, deny access
          if user.restaurant_id != restaurant_id.to_i
            Rails.logger.warn { "User #{user.email} (restaurant_id: #{user.restaurant_id}) attempted to access restaurant_id: #{restaurant_id}" }
            return { success: false, errors: ["You do not have access to this restaurant"], status: :forbidden }
          end
        end
        
        # Generate token using TokenService
        # For super_admin users, we can use the requested restaurant_id if provided
        token_restaurant_id = user.role == "super_admin" ? restaurant_id : user.restaurant_id
        token = TokenService.generate_token(user, token_restaurant_id)
        
        # Track successful login
        analytics.track("user.login.success", { user_id: user.id, restaurant_id: token_restaurant_id || user.restaurant_id })
        
        { success: true, token: token, user: user }
      else
        # Track failed login attempt
        analytics.track("user.login.failed", { email: email.to_s.downcase })
        
        { success: false, errors: ["Invalid email or password"], status: :unauthorized }
      end
    rescue => e
      { success: false, errors: ["Authentication failed: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Log out a user by revoking their token
  def logout(token, current_user = nil)
    begin
      if token
        # Revoke the token
        TokenService.revoke_token(token)
        
        # Track logout
        analytics.track("user.logout", { user_id: current_user&.id }) if current_user
      end
      
      { success: true, message: "Logged out successfully" }
    rescue => e
      { success: false, errors: ["Logout failed: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Switch tenant for a user (only available to super_admin users)
  def switch_tenant(current_user, restaurant_id, current_token)
    begin
      # Only super_admin users can switch tenants
      unless current_user.super_admin?
        Rails.logger.warn { "Non-super_admin user #{current_user.email} attempted to switch tenant to restaurant_id: #{restaurant_id}" }
        return { success: false, errors: ["Only super_admin users can switch tenants"], status: :forbidden }
      end
      
      # Verify the restaurant exists
      restaurant = Restaurant.find_by(id: restaurant_id)
      
      unless restaurant
        return { success: false, errors: ["Restaurant not found"], status: :not_found }
      end
      
      # Revoke the current token
      TokenService.revoke_token(current_token) if current_token
      
      # Generate a new token for the requested restaurant
      new_token = TokenService.generate_token(current_user, restaurant_id)
      
      # Track tenant switch
      analytics.track("user.switch_tenant", {
        user_id: current_user.id,
        from_restaurant_id: current_user.restaurant_id,
        to_restaurant_id: restaurant_id
      })
      
      { success: true, token: new_token, user: current_user }
    rescue => e
      { success: false, errors: ["Tenant switch failed: #{e.message}"], status: :internal_server_error }
    end
  end
end
