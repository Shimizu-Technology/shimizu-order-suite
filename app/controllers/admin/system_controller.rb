module Admin
  class SystemController < ApplicationController
    before_action :authorize_admin, except: [:test_pushover, :validate_pushover_key, :test_sms, :generate_web_push_keys]
    
    def test_sms
      to = params[:phone]
      body = "This is a test message from #{Rails.application.class.module_parent_name} at #{Time.current.strftime('%H:%M:%S')}"
      
      result = ClicksendClient.send_text_message(
        to: to,
        body: body,
        from: params[:from] || "Test"
      )
      
      if result
        render json: { status: "success", message: "Test SMS queued for delivery" }
      else
        render json: { status: "error", message: "Failed to send test SMS" }, status: :internal_server_error
      end
    end
    
    def test_pushover
      user_key = params[:user_key]
      
      if user_key.blank?
        return render json: { error: "User key is required" }, status: :bad_request
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
        render json: { status: "success", message: "Test notification sent successfully" }
      else
        render json: { status: "error", message: "Failed to send test notification" }, status: :internal_server_error
      end
    end
    
    def validate_pushover_key
      user_key = params[:user_key]
      
      if user_key.blank?
        return render json: { error: "User key is required" }, status: :bad_request
      end
      
      # Validate the user key
      valid = PushoverClient.validate_user_key(user_key, params[:app_token])
      
      if valid
        render json: { status: "success", message: "User key is valid", valid: true }
      else
        render json: { status: "error", message: "User key is invalid or could not be validated", valid: false }
      end
    end
    
    def generate_web_push_keys
      # Get restaurant ID from params
      restaurant_id = params[:restaurant_id]
      
      # Log the request
      Rails.logger.info("Generating VAPID keys for restaurant_id: #{restaurant_id}")
      
      # Find the restaurant
      begin
        restaurant = Restaurant.find_by(id: restaurant_id)
        
        # Ensure we have a restaurant
        unless restaurant
          Rails.logger.error("Restaurant not found with ID: #{restaurant_id}")
          return render json: { error: "Restaurant not found" }, status: :not_found
        end
        
        Rails.logger.info("Restaurant found: #{restaurant.name}")
        
        # Make sure the webpush gem is available
        unless defined?(Webpush)
          Rails.logger.error("Webpush gem is not available")
          return render json: { 
            status: "error", 
            message: "Webpush gem is not available" 
          }, status: :internal_server_error
        end
        
        # Explicitly require the webpush gem
        begin
          require 'webpush'
          Rails.logger.info("Webpush gem successfully required")
        rescue LoadError => e
          Rails.logger.error("Failed to require webpush gem: #{e.message}")
          return render json: { 
            status: "error", 
            message: "Failed to require webpush gem: #{e.message}" 
          }, status: :internal_server_error
        end
        
        # Generate new VAPID keys
        begin
          # Use the Webpush class directly instead of the restaurant method
          vapid_keys = Webpush.generate_key
          
          # Update the restaurant's admin_settings
          admin_settings = restaurant.admin_settings || {}
          admin_settings["web_push"] ||= {}
          admin_settings["web_push"]["vapid_public_key"] = vapid_keys[:public_key]
          admin_settings["web_push"]["vapid_private_key"] = vapid_keys[:private_key]
          
          # Save the settings
          restaurant.update(admin_settings: admin_settings)
          
          Rails.logger.info("VAPID keys generated successfully")
          
          render json: { 
            status: "success", 
            message: "VAPID keys generated successfully",
            public_key: vapid_keys[:public_key],
            private_key: vapid_keys[:private_key]
          }
        rescue => e
          Rails.logger.error("Failed to generate VAPID keys: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          render json: { 
            status: "error", 
            message: "Failed to generate VAPID keys: #{e.message}" 
          }, status: :internal_server_error
        end
      rescue => e
        Rails.logger.error("Error in generate_web_push_keys: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render json: { 
          status: "error", 
          message: "Error in generate_web_push_keys: #{e.message}" 
        }, status: :internal_server_error
      end
    end
    
    private
    
    def authorize_admin
      unless current_user&.role.in?(%w[admin super_admin])
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
    
    # Mark these endpoints as public (no restaurant context required)
    def public_endpoint?
      ["test_pushover", "validate_pushover_key", "test_sms", "generate_web_push_keys"].include?(action_name)
    end
  end
end
