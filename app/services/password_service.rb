# app/services/password_service.rb
class PasswordService
  attr_reader :analytics
  
  def initialize(analytics_service = nil)
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Handle forgot password request
  def forgot_password(email, restaurant_id = nil)
    begin
      downcased_email = email.to_s.downcase
      user = nil
      
      # If restaurant_id is provided, find user in that specific restaurant
      if restaurant_id.present?
        user = User.find_by("LOWER(email) = ? AND restaurant_id = ?", downcased_email, restaurant_id.to_i)
      end
      
      # If no user found or no restaurant_id provided, try to find any user with this email
      # This maintains backward compatibility with existing password reset flows
      if user.nil?
        users = User.where("LOWER(email) = ?", downcased_email).to_a
        
        # If multiple users found (same email across different restaurants),
        # prioritize in this order: 1) super_admin, 2) admin, 3) staff, 4) customer
        if users.size > 1
          user = users.find { |u| u.role == 'super_admin' } || 
                 users.find { |u| u.role == 'admin' } || 
                 users.find { |u| u.role == 'staff' } || 
                 users.first
        else
          user = users.first
        end
      end
      
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
  def reset_password(email, token, new_password, new_password_confirmation, restaurant_id = nil)
    begin
      downcased_email = email.to_s.downcase
      user = nil
      
      # If restaurant_id is provided, find user in that specific restaurant
      if restaurant_id.present?
        user = User.find_by("LOWER(email) = ? AND restaurant_id = ?", downcased_email, restaurant_id.to_i)
      end
      
      # If no user found or no restaurant_id provided, try to find any user with this email
      # This maintains backward compatibility with existing password reset flows
      if user.nil?
        users = User.where("LOWER(email) = ?", downcased_email).to_a
        
        # If multiple users found (same email across different restaurants),
        # prioritize in this order: 1) super_admin, 2) admin, 3) staff, 4) customer
        if users.size > 1
          user = users.find { |u| u.role == 'super_admin' } || 
                 users.find { |u| u.role == 'admin' } || 
                 users.find { |u| u.role == 'staff' } || 
                 users.first
        else
          user = users.first
        end
      end
      
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
