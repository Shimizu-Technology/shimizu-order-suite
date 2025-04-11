# app/services/push_subscription_service.rb
class PushSubscriptionService
  attr_reader :current_restaurant, :analytics
  
  def initialize(current_restaurant = nil, analytics_service = nil)
    @current_restaurant = current_restaurant
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # List all push subscriptions for the current restaurant
  def list_subscriptions(current_user)
    begin
      # Ensure user has permission to manage the restaurant
      unless current_user.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Unauthorized - Admin access required"], status: :forbidden }
      end
      
      subscriptions = current_restaurant.push_subscriptions.active
      
      subscription_data = subscriptions.map do |sub|
        {
          id: sub.id,
          endpoint: sub.endpoint,
          user_agent: sub.user_agent,
          created_at: sub.created_at
        }
      end
      
      # Track analytics
      analytics.track("push_subscriptions.listed", {
        restaurant_id: current_restaurant.id,
        user_id: current_user.id,
        count: subscriptions.count
      })
      
      { success: true, subscriptions: subscription_data }
    rescue => e
      { success: false, errors: ["Failed to retrieve push subscriptions: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Create a new push subscription
  def create_subscription(subscription_params, user_agent, restaurant_id = nil)
    begin
      # Use the provided restaurant_id or fall back to current_restaurant
      restaurant = if restaurant_id.present?
                     Restaurant.find_by(id: restaurant_id)
                   else
                     current_restaurant
                   end
      
      unless restaurant
        return { success: false, errors: ["Restaurant not found"], status: :not_found }
      end
      
      # Create or update the subscription
      subscription = restaurant.push_subscriptions.find_or_initialize_by(
        endpoint: subscription_params[:endpoint]
      )
      
      subscription.p256dh_key = subscription_params[:keys][:p256dh]
      subscription.auth_key = subscription_params[:keys][:auth]
      subscription.user_agent = user_agent
      subscription.active = true
      
      if subscription.save
        # Track analytics
        analytics.track("push_subscription.created", {
          restaurant_id: restaurant.id,
          subscription_id: subscription.id
        })
        
        { success: true, id: subscription.id }
      else
        { success: false, errors: subscription.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to create push subscription: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Delete a push subscription
  def delete_subscription(id, current_user)
    begin
      # Ensure user has permission to manage the restaurant
      unless current_user.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Unauthorized - Admin access required"], status: :forbidden }
      end
      
      subscription = current_restaurant.push_subscriptions.find_by(id: id)
      
      unless subscription
        return { success: false, errors: ["Subscription not found"], status: :not_found }
      end
      
      if subscription.deactivate!
        # Track analytics
        analytics.track("push_subscription.deleted", {
          restaurant_id: current_restaurant.id,
          user_id: current_user.id,
          subscription_id: subscription.id
        })
        
        { success: true }
      else
        { success: false, errors: ["Failed to deactivate subscription"], status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to delete push subscription: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Unsubscribe the current device
  def unsubscribe(subscription_params, restaurant_id = nil)
    begin
      # Use the provided restaurant_id or fall back to current_restaurant
      restaurant = if restaurant_id.present?
                     Restaurant.find_by(id: restaurant_id)
                   else
                     current_restaurant
                   end
      
      unless restaurant
        return { success: false, errors: ["Restaurant not found"], status: :not_found }
      end
      
      subscription = restaurant.push_subscriptions.find_by(
        endpoint: subscription_params[:endpoint]
      )
      
      if subscription
        if subscription.deactivate!
          # Track analytics
          analytics.track("push_subscription.unsubscribed", {
            restaurant_id: restaurant.id,
            subscription_id: subscription.id
          })
          
          { success: true }
        else
          { success: false, errors: ["Failed to deactivate subscription"], status: :unprocessable_entity }
        end
      else
        { success: false, errors: ["Subscription not found"], status: :not_found }
      end
    rescue => e
      { success: false, errors: ["Failed to unsubscribe: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Get the VAPID public key for a restaurant
  def get_vapid_public_key(restaurant_id = nil)
    begin
      # Use the provided restaurant_id or fall back to current_restaurant
      restaurant = if restaurant_id.present?
                     Restaurant.find_by(id: restaurant_id)
                   else
                     current_restaurant
                   end
      
      unless restaurant
        return { success: false, errors: ["Restaurant not found"], status: :not_found }
      end
      
      # Check if web push is enabled for the restaurant
      if restaurant.web_push_enabled?
        Rails.logger.info("Web push is enabled for restaurant #{restaurant.id}")
        Rails.logger.info("VAPID public key: #{restaurant.web_push_vapid_keys[:public_key]}")
        
        { 
          success: true,
          vapid_public_key: restaurant.web_push_vapid_keys[:public_key],
          enabled: true
        }
      else
        Rails.logger.info("Web push is not enabled for restaurant #{restaurant.id}")
        
        # Check if notification channels are configured
        if restaurant.admin_settings&.dig("notification_channels", "orders", "web_push") == true
          Rails.logger.info("Web push is enabled in notification channels but VAPID keys are missing")
        else
          Rails.logger.info("Web push is not enabled in notification channels")
        end
        
        # Check if VAPID keys are present
        if restaurant.admin_settings&.dig("web_push", "vapid_public_key").present?
          Rails.logger.info("VAPID public key is present")
        else
          Rails.logger.info("VAPID public key is missing")
        end
        
        if restaurant.admin_settings&.dig("web_push", "vapid_private_key").present?
          Rails.logger.info("VAPID private key is present")
        else
          Rails.logger.info("VAPID private key is missing")
        end
        
        # Return the public key even if web push is not enabled
        # This allows the frontend to subscribe to push notifications
        # even if the restaurant hasn't enabled them yet
        if restaurant.admin_settings&.dig("web_push", "vapid_public_key").present?
          { 
            success: true,
            vapid_public_key: restaurant.admin_settings.dig("web_push", "vapid_public_key"),
            enabled: false
          }
        else
          { success: true, enabled: false }
        end
      end
    rescue => e
      { success: false, errors: ["Failed to get VAPID public key: #{e.message}"], status: :internal_server_error }
    end
  end
end
