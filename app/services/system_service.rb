# app/services/system_service.rb
class SystemService < TenantScopedService
  # This service handles system-level operations
  # Some operations are tenant-scoped, while others are global (super_admin only)
  
  attr_accessor :current_user
  
  # Test SMS functionality
  def test_sms(params)
    to = params[:phone]
    body = "This is a test message from #{Rails.application.class.module_parent_name} at #{Time.current.strftime('%H:%M:%S')}"
    
    result = ClicksendClient.send_text_message(
      to: to,
      body: body,
      from: params[:from] || "Test"
    )
    
    if result
      { success: true, message: "Test SMS queued for delivery" }
    else
      { success: false, message: "Failed to send test SMS", status: :internal_server_error }
    end
  end
  
  # Test Pushover notification
  def test_pushover(params)
    user_key = params[:user_key]
    
    if user_key.blank?
      return { success: false, message: "User key is required", status: :bad_request }
    end
    
    message = params[:message] || "This is a test notification from #{Rails.application.class.module_parent_name} at #{Time.current.strftime('%H:%M:%S')}"
    title = params[:title] || "Test Notification"
    
    # Send test notification
    success = PushoverClient.send_notification(
      user_key: user_key,
      message: message,
      title: title,
      app_token: params[:app_token],
      priority: params[:priority]&.to_i || 0,
      sound: params[:sound]
    )
    
    if success
      { success: true, message: "Test notification sent successfully" }
    else
      { success: false, message: "Failed to send test notification", status: :internal_server_error }
    end
  end
  
  # Validate Pushover key
  def validate_pushover_key(params)
    user_key = params[:user_key]
    
    if user_key.blank?
      return { success: false, message: "User key is required", status: :bad_request }
    end
    
    # Validate the user key
    valid = PushoverClient.validate_user_key(user_key, params[:app_token])
    
    if valid
      { success: true, message: "User key is valid", valid: true }
    else
      { success: false, message: "User key is invalid or could not be validated", valid: false }
    end
  end
  
  # Generate web push keys for a restaurant
  def generate_web_push_keys(restaurant_id = nil, user = nil)
    # Log the request
    Rails.logger.info("Generating VAPID keys for restaurant_id: #{restaurant_id || @restaurant&.id}")
    
    begin
      # Determine which restaurant to use
      # If user is super_admin and a different restaurant_id is provided, use that restaurant
      # Otherwise, use the restaurant that was passed to the service constructor
      restaurant = if user&.super_admin? && restaurant_id.present? && restaurant_id.to_s != @restaurant&.id.to_s
                     Restaurant.find_by(id: restaurant_id)
                   else
                     @restaurant
                   end
      
      # Ensure we have a restaurant
      unless restaurant
        Rails.logger.error("Restaurant not found with ID: #{restaurant_id}")
        return { success: false, message: "Restaurant not found", status: :not_found }
      end
      
      Rails.logger.info("Restaurant found: #{restaurant.name}")
      
      # Generate new VAPID keys using the Restaurant model's method
      begin
        # Call the restaurant model's method to generate VAPID keys
        vapid_keys = restaurant.generate_web_push_vapid_keys!
        
        Rails.logger.info("VAPID keys generated successfully")
        Rails.logger.info("Public key: #{vapid_keys[:public_key]}")
        Rails.logger.info("Public key length: #{vapid_keys[:public_key].length}")
        
        { 
          success: true, 
          message: "VAPID keys generated successfully",
          public_key: vapid_keys[:public_key],
          private_key: vapid_keys[:private_key]
        }
      rescue => e
        Rails.logger.error("Failed to generate VAPID keys: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        { 
          success: false, 
          message: "Failed to generate VAPID keys: #{e.message}",
          status: :internal_server_error
        }
      end
    rescue => e
      Rails.logger.error("Error in generate_web_push_keys: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      { 
        success: false, 
        message: "Error in generate_web_push_keys: #{e.message}",
        status: :internal_server_error
      }
    end
  end
  
  private
  
  # Get the current user from the service context
  def current_user
    @current_user
  end
  
  # Set the current user for the service
  def current_user=(user)
    @current_user = user
  end
end
