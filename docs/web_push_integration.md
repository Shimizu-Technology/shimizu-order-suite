# Web Push Notifications Integration Guide (Backend)

This document explains how web push notifications are implemented in the Hafaloha API.

## Overview

Web push notifications allow the application to send notifications to users even when they are not actively using the application. This is particularly useful for notifying restaurant staff about new orders.

The implementation uses the Web Push API, which is supported by most modern browsers. On iOS devices (iPad/iPhone), web push notifications are supported in iOS 16.4+ when the web app is installed as a PWA (Progressive Web App).

## Backend Components

The backend implementation consists of the following components:

1. **Push Subscriptions Controller**: Manages push subscription endpoints
2. **Web Push Notification Job**: Sends push notifications to subscribed devices
3. **Restaurant Model**: Stores VAPID keys and notification settings
4. **Push Subscription Model**: Stores subscription details for each device
5. **Admin System Controller**: Provides endpoints for generating VAPID keys

## Database Schema

### Push Subscriptions Table

```ruby
create_table :push_subscriptions do |t|
  t.references :restaurant, index: true, foreign_key: true
  t.string :endpoint, null: false
  t.string :p256dh_key, null: false
  t.string :auth_key, null: false
  t.string :user_agent
  t.boolean :active, default: true
  t.timestamps
end
```

### Restaurant Model Extensions

The Restaurant model has been extended with the following methods:

```ruby
# Check if web push is enabled for this restaurant
def web_push_enabled?
  admin_settings&.dig("notification_channels", "orders", "web_push") == true && 
    admin_settings&.dig("web_push", "vapid_public_key").present? &&
    admin_settings&.dig("web_push", "vapid_private_key").present?
end

# Get the VAPID keys for this restaurant
def web_push_vapid_keys
  {
    public_key: admin_settings&.dig("web_push", "vapid_public_key"),
    private_key: admin_settings&.dig("web_push", "vapid_private_key")
  }
end

# Generate new VAPID keys for this restaurant
def generate_web_push_vapid_keys!
  vapid_keys = Webpush.generate_key
  
  # Update admin_settings
  new_settings = admin_settings || {}
  new_settings["web_push"] ||= {}
  new_settings["web_push"]["vapid_public_key"] = vapid_keys[:public_key]
  new_settings["web_push"]["vapid_private_key"] = vapid_keys[:private_key]
  
  # Save the settings
  update(admin_settings: new_settings)
  
  vapid_keys
end

# Send a web push notification to all subscribed devices
def send_web_push_notification(payload, options = {})
  return false unless web_push_enabled?
  
  # Call the job with positional parameters
  SendWebPushNotificationJob.perform_later(
    id, # restaurant_id
    payload,
    options
  )
  
  true
end
```

## API Endpoints

### Push Subscriptions Controller

```ruby
# GET /push_subscriptions/vapid_public_key
# Get the VAPID public key for the current restaurant
def vapid_public_key
  # Extract restaurant_id from params or subdomain
  restaurant_id = params[:restaurant_id]
  
  # Find the restaurant
  restaurant = if restaurant_id.present?
                 Restaurant.find_by(id: restaurant_id)
               else
                 @restaurant
               end
  
  # Return error if restaurant not found
  unless restaurant
    render json: { error: "Restaurant not found" }, status: :not_found
    return
  end
  
  # Check if web push is enabled for the restaurant
  if restaurant.web_push_enabled?
    render json: { 
      vapid_public_key: restaurant.web_push_vapid_keys[:public_key],
      enabled: true
    }
  else
    render json: { enabled: false }
  end
end

# POST /push_subscriptions
# Create a new push subscription
def create
  # Extract subscription details from params
  subscription_params = params.require(:subscription)
  
  # Extract restaurant_id from params
  restaurant_id = params[:restaurant_id]
  
  # Find the restaurant
  restaurant = if restaurant_id.present?
                 Restaurant.find_by(id: restaurant_id)
               else
                 @restaurant
               end
  
  # Return error if restaurant not found
  unless restaurant
    render json: { error: "Restaurant not found" }, status: :not_found
    return
  end
  
  # Create or update the subscription
  subscription = restaurant.push_subscriptions.find_or_initialize_by(
    endpoint: subscription_params[:endpoint]
  )
  
  subscription.p256dh_key = subscription_params[:keys][:p256dh]
  subscription.auth_key = subscription_params[:keys][:auth]
  subscription.user_agent = request.user_agent
  subscription.active = true
  
  if subscription.save
    render json: { status: 'success', id: subscription.id }
  else
    render json: { status: 'error', errors: subscription.errors.full_messages }, status: :unprocessable_entity
  end
end

# POST /push_subscriptions/unsubscribe
# Unsubscribe the current device
def unsubscribe
  subscription_params = params.require(:subscription)
  
  # Extract restaurant_id from params
  restaurant_id = params[:restaurant_id]
  
  # Find the restaurant
  restaurant = if restaurant_id.present?
                 Restaurant.find_by(id: restaurant_id)
               else
                 @restaurant
               end
  
  # Return error if restaurant not found
  unless restaurant
    render json: { error: "Restaurant not found" }, status: :not_found
    return
  end
  
  subscription = restaurant.push_subscriptions.find_by(
    endpoint: subscription_params[:endpoint]
  )
  
  if subscription
    subscription.deactivate!
    render json: { status: 'success' }
  else
    render json: { status: 'error', message: 'Subscription not found' }, status: :not_found
  end
end
```

## Web Push Notification Job

```ruby
class SendWebPushNotificationJob < ApplicationJob
  queue_as :default
  
  # Retry options
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
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
        # Send the push notification
        Webpush.payload_send(
          message: message,
          endpoint: subscription.endpoint,
          p256dh: subscription.p256dh_key,
          auth: subscription.auth_key,
          vapid: vapid
        )
        
        Rails.logger.info("Web push notification sent to subscription #{subscription.id} for restaurant #{restaurant_id}")
      rescue Webpush::InvalidSubscription => e
        # The subscription is no longer valid, mark it as inactive
        Rails.logger.info("Invalid subscription #{subscription.id} for restaurant #{restaurant_id}: #{e.message}")
        subscription.deactivate!
      rescue Webpush::ExpiredSubscription => e
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
```

## Integration with Order Model

To send notifications when a new order is created, the Order model has been updated:

```ruby
class Order < ApplicationRecord
  after_create :notify_restaurant
  
  private
  
  def notify_restaurant
    # Send push notification if enabled
    if restaurant.web_push_enabled?
      restaurant.send_web_push_notification({
        title: "New Order ##{id}",
        body: "Order total: $#{total}",
        icon: "/icons/icon-192.png",
        data: {
          orderId: id,
          url: "/admin/orders/#{id}"
        }
      })
    end
    
    # Other notification methods (SMS, email, etc.)
    # ...
  end
end
```

## Admin System Controller

The Admin::SystemController has been updated to include methods for generating VAPID keys:

```ruby
# POST /admin/generate_web_push_keys
# Generate new VAPID keys for the current restaurant
def generate_web_push_keys
  authorize! :manage, current_restaurant
  
  vapid_keys = current_restaurant.generate_web_push_vapid_keys!
  
  render json: {
    status: 'success',
    vapid_public_key: vapid_keys[:public_key],
    vapid_private_key: vapid_keys[:private_key]
  }
end
```

## Security Considerations

1. **VAPID Keys**: The VAPID private key should be kept secure and never exposed to the client.
2. **HTTPS**: Web Push requires HTTPS in production.
3. **Authentication**: Admin endpoints (like listing subscriptions) require authentication.
4. **Data Privacy**: The push payload is encrypted end-to-end, but the subscription endpoints may reveal some metadata.

## Troubleshooting

### Common Issues

1. **Invalid Subscription**: If a subscription becomes invalid (e.g., the user uninstalled the PWA), the push service will return a 404 or 410 error. The job will mark the subscription as inactive.
2. **Missing VAPID Keys**: If the VAPID keys are missing or invalid, the push notification will fail.
3. **Push Service Errors**: The push service may return errors if the payload is too large or if there are rate limiting issues.

### Debugging

To debug push notification issues:

1. Check the Rails logs for errors
2. Verify that the subscription is stored in the database
3. Check that the VAPID keys are properly configured
4. Use the Rails console to manually send a test notification

## References

- [Web Push API Documentation](https://developer.mozilla.org/en-US/docs/Web/API/Push_API)
- [Webpush Gem Documentation](https://github.com/zaru/webpush)
- [VAPID Protocol](https://datatracker.ietf.org/doc/html/rfc8292)
