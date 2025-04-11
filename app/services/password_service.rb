# app/services/password_service.rb
class PasswordService
  attr_reader :analytics
  
  def initialize(analytics_service = nil)
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Handle forgot password request
  def forgot_password(email)
    begin
      user = User.find_by(email: email.to_s.downcase)
      
      if user
        # 1) Generate the reset token
        raw_token = user.generate_reset_password_token!
        
        # 2) Send the email with the raw token
        PasswordMailer.reset_password(user, raw_token).deliver_later
        
        # Track password reset request
        analytics.track("user.password.reset_requested", { user_id: user.id })
      else
        # Track failed password reset request
        analytics.track("user.password.reset_requested_invalid_email", { email: email.to_s.downcase })
      end
      
      # Return a generic message to avoid email enumeration
      { success: true, message: "If that email exists, a reset link has been sent." }
    rescue => e
      { success: false, errors: ["Password reset request failed: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Handle password reset
  def reset_password(email, token, new_password, new_password_confirmation)
    begin
      user = User.find_by(email: email.to_s.downcase)
      
      unless user
        return { success: false, errors: ["Invalid link or user not found"], status: :unprocessable_entity }
      end
      
      # Check if the token is valid & not expired
      unless user.reset_token_valid?(token)
        # Track invalid token attempt
        analytics.track("user.password.reset_invalid_token", { user_id: user.id })
        return { success: false, errors: ["Invalid or expired token"], status: :unprocessable_entity }
      end
      
      # Update the user's password
      user.password = new_password
      user.password_confirmation = new_password_confirmation
      
      if user.save
        # Clear token so it can't be reused
        user.clear_reset_password_token!
        
        # Generate a new JWT using TokenService so the user can be auto-logged in
        jwt = TokenService.generate_token(user)
        
        # Track successful password reset
        analytics.track("user.password.reset_success", { user_id: user.id })
        
        # Return both the token and the user object => front end can store them
        { 
          success: true, 
          message: "Password updated successfully.",
          token: jwt,
          user: user
        }
      else
        # Track failed password reset
        analytics.track("user.password.reset_failed", { 
          user_id: user.id,
          errors: user.errors.full_messages
        })
        
        { success: false, errors: user.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Password reset failed: #{e.message}"], status: :internal_server_error }
    end
  end
end
