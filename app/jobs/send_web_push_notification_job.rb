# app/jobs/send_web_push_notification_job.rb

class SendWebPushNotificationJob < ApplicationJob
  queue_as :notifications
  
  # Less critical, can be dropped after 3 hours if not processed
  sidekiq_options retry: 5, expires_in: 3.hours
  
  def perform(restaurant_id, payload)
    # Find the restaurant
    restaurant = Restaurant.find_by(id: restaurant_id)
    return unless restaurant
    
    # Check if web push is enabled for this restaurant
    return unless restaurant.web_push_enabled?
    
    # Get the VAPID keys
    vapid_keys = restaurant.web_push_vapid_keys
    return unless vapid_keys && vapid_keys[:public_key].present? && vapid_keys[:private_key].present?
    
    # Get all active subscriptions for this restaurant
    subscriptions = restaurant.push_subscriptions.active
    
    # If there are no subscriptions, log and return
    if subscriptions.empty?
      Rails.logger.info("No active web push subscriptions found for restaurant #{restaurant_id}")
      return
    end
    
    # Convert payload to JSON string
    message = payload.is_a?(String) ? payload : payload.to_json
    
    # Set up VAPID details
    vapid = {
      subject: "mailto:#{restaurant.contact_email || 'notifications@hafaloha.com'}",
      public_key: vapid_keys[:public_key],
      private_key: vapid_keys[:private_key]
    }
    
    # Send push notification to each subscription
    subscriptions.find_each do |subscription|
      begin
        # Create subscription object for WebPush
        subscription_info = {
          endpoint: subscription.endpoint,
          keys: {
            p256dh: subscription.p256dh_key,
            auth: subscription.auth_key
          }
        }
        
        # Send the push notification
        WebPush.payload_send(
          message: message,
          endpoint: subscription.endpoint,
          p256dh: subscription.p256dh_key,
          auth: subscription.auth_key,
          vapid: vapid
        )
        
        Rails.logger.info("Web push notification sent to subscription #{subscription.id} for restaurant #{restaurant_id}")
      rescue WebPush::InvalidSubscription => e
        # The subscription is no longer valid, mark it as inactive
        Rails.logger.info("Invalid subscription #{subscription.id} for restaurant #{restaurant_id}: #{e.message}")
        subscription.deactivate!
      rescue WebPush::ExpiredSubscription => e
        # The subscription has expired, mark it as inactive
        Rails.logger.info("Expired subscription #{subscription.id} for restaurant #{restaurant_id}: #{e.message}")
        subscription.deactivate!
      rescue => e
        # Log other errors but don't mark the subscription as inactive
        Rails.logger.error("Error sending web push notification to subscription #{subscription.id} for restaurant #{restaurant_id}: #{e.message}")
      end
    end
  end
end
