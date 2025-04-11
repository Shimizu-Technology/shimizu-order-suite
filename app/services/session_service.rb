# app/services/session_service.rb
class SessionService
  attr_reader :analytics
  
  def initialize(analytics_service = nil)
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Authenticate a user with email and password
  def authenticate(email, password)
    begin
      # 1) We downcase the email => "john@EXAMPLE.com" => "john@example.com"
      # 2) Find by LOWER(email) = downcased email
      user = User.find_by(
        "LOWER(email) = ?",
        email.to_s.downcase
      )
      
      if user && user.authenticate(password)
        # Generate token using TokenService
        token = TokenService.generate_token(user)
        
        # Track successful login
        analytics.track("user.login.success", { user_id: user.id })
        
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
  
  # Switch tenant for a user
  def switch_tenant(current_user, restaurant_id, current_token)
    begin
      # Verify the restaurant exists
      restaurant = Restaurant.find_by(id: restaurant_id)
      
      unless restaurant
        return { success: false, errors: ["Restaurant not found"], status: :not_found }
      end
      
      # Verify user has access to the requested restaurant
      unless current_user.super_admin? || current_user.restaurant_id == restaurant.id
        return { success: false, errors: ["You don't have access to this restaurant"], status: :forbidden }
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
