# Web Push Notifications Integration (Backend)

This document describes the backend implementation of Web Push notifications in the Hafaloha application.

## Overview

Web Push notifications allow the application to send notifications to users' devices even when they are not actively using the application. This is particularly useful for notifying restaurant staff about new orders or other important events.

## Components

### Models

#### PushSubscription Model

```ruby
# app/models/push_subscription.rb
class PushSubscription < ApplicationRecord
  belongs_to :restaurant
  
  scope :active, -> { where(active: true) }
  
  def deactivate!
    update(active: false)
  end
end
```

The PushSubscription model stores the subscription information for each device:
- `endpoint`: The URL to which push messages should be sent
- `p256dh_key`: The P-256 ECDH public key
- `auth_key`: The authentication secret
- `active`: Whether the subscription is active
- `user_agent`: The user agent of the device

### Controllers

#### PushSubscriptionsController

```ruby
# app/controllers/push_subscriptions_controller.rb
class PushSubscriptionsController < ApplicationController
  before_action :authenticate_user!, only: [:index, :destroy]
  before_action :set_restaurant
  
  # GET /api/push_subscriptions
  def index
    authorize! :manage, @restaurant
    subscriptions = @restaurant.push_subscriptions.active
    render json: { subscriptions: subscriptions.map { |sub| { id: sub.id, endpoint: sub.endpoint, user_agent: sub.user_agent, created_at: sub.created_at } } }
  end
  
  # POST /api/push_subscriptions
  def create
    subscription_params = params.require(:subscription)
    subscription = @restaurant.push_subscriptions.find_or_initialize_by(endpoint: subscription_params[:endpoint])
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
  
  # DELETE /api/push_subscriptions/:id
  def destroy
    authorize! :manage, @restaurant
    subscription = @restaurant.push_subscriptions.find(params[:id])
    subscription.deactivate!
    render json: { status: 'success' }
  end
  
  # POST /api/push_subscriptions/unsubscribe
  def unsubscribe
    subscription_params = params.require(:subscription)
    subscription = @restaurant.push_subscriptions.find_by(endpoint: subscription_params[:endpoint])
    
    if subscription
      subscription.deactivate!
      render json: { status: 'success' }
    else
      render json: { status: 'error', message: 'Subscription not found' }, status: :not_found
    end
  end
  
  # GET /api/push_subscriptions/vapid_public_key
  def vapid_public_key
    if @restaurant.web_push_enabled?
      render json: { vapid_public_key: @restaurant.web_push_vapid_keys[:public_key], enabled: true }
    else
      render json: { enabled: false }
    end
  end
  
  private
  
  def set_restaurant
    @restaurant = current_restaurant
  end
end
```

### Background Jobs

#### SendWebPushNotificationJob

```ruby
# app/jobs/send_web_push_notification_job.rb
class SendWebPushNotificationJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(restaurant_id, payload)
    restaurant = Restaurant.find_by(id: restaurant_id)
    return unless restaurant
    
    return unless restaurant.web_push_enabled?
    
    vapid_keys = restaurant.web_push_vapid_keys
    return unless vapid_keys && vapid_keys[:public_key].present? && vapid_keys[:private_key].present?
    
    subscriptions = restaurant.push_subscriptions.active
    
    if subscriptions.empty?
      Rails.logger.info("No active web push subscriptions found for restaurant #{restaurant_id}")
      return
    end
    
    message = payload.is_a?(String) ? payload : payload.to_json
    
    vapid = {
      subject: "mailto:#{restaurant.contact_email || 'notifications@hafaloha.com'}",
      public_key: vapid_keys[:public_key],
      private_key: vapid_keys[:private_key]
    }
    
    subscriptions.find_each do |subscription|
      begin
        Webpush.payload_send(
          message: message,
          endpoint: subscription.endpoint,
          p256dh: subscription.p256dh_key,
          auth: subscription.auth_key,
          vapid: vapid
        )
        
        Rails.logger.info("Web push notification sent to subscription #{subscription.id} for restaurant #{restaurant_id}")
      rescue Webpush::InvalidSubscription => e
        Rails.logger.info("Invalid subscription #{subscription.id} for restaurant #{restaurant_id}: #{e.message}")
        subscription.deactivate!
      rescue Webpush::ExpiredSubscription => e
        Rails.logger.info("Expired subscription #{subscription.id} for restaurant #{restaurant_id}: #{e.message}")
        subscription.deactivate!
      rescue => e
        Rails.logger.error("Error sending web push notification to subscription #{subscription.id} for restaurant #{restaurant_id}: #{e.message}")
      end
    end
  end
end
```

### Restaurant Model Extensions

```ruby
# app/models/restaurant.rb (web push related methods)
class Restaurant < ApplicationRecord
  has_many :push_subscriptions, dependent: :destroy
  
  # Web Push-related methods
  def web_push_enabled?
    admin_settings&.dig("notification_channels", "orders", "web_push") == true && 
      admin_settings&.dig("web_push", "vapid_public_key").present? &&
      admin_settings&.dig("web_push", "vapid_private_key").present?
  end
  
  def web_push_vapid_keys
    {
      public_key: admin_settings&.dig("web_push", "vapid_public_key"),
      private_key: admin_settings&.dig("web_push", "vapid_private_key")
    }
  end
  
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
end
```

### Order Model Integration

```ruby
# app/models/order.rb (web push notification method)
class Order < ApplicationRecord
  after_create :notify_web_push
  
  private
  
  def notify_web_push
    return if Rails.env.test?
    return unless restaurant.web_push_enabled?
    
    # Format the order items for the notification
    food_item_lines = items.map do |item|
      "#{item['name']} (x#{item['quantity']}): $#{'%.2f' % item['price']}"
    end.join(", ")
    
    # Create the notification payload
    payload = {
      title: "New Order ##{id}",
      body: "Total: $#{'%.2f' % total.to_f} - #{food_item_lines}",
      icon: "/icons/icon-192.png",
      badge: "/icons/badge-96.png",
      tag: "new-order-#{id}",
      data: {
        url: "/admin/orders/#{id}",
        orderId: id,
        timestamp: Time.current.to_i
      },
      actions: [
        {
          action: "view",
          title: "View Order"
        },
        {
          action: "acknowledge",
          title: "Acknowledge"
        }
      ]
    }
    
    # Enqueue the Web Push notification job
    SendWebPushNotificationJob.perform_later(
      restaurant_id,
      payload
    )
  end
end
```

### Admin System Controller

```ruby
# app/controllers/admin/system_controller.rb (web push related methods)
module Admin
  class SystemController < ApplicationController
    def generate_web_push_keys
      # Ensure we have a restaurant context
      unless current_restaurant
        return render json: { error: "Restaurant context required" }, status: :bad_request
      end
      
      # Generate new VAPID keys
      begin
        # Make sure the webpush gem is available
        unless defined?(Webpush)
          return render json: { 
            status: "error", 
            message: "Webpush gem is not available" 
          }, status: :internal_server_error
        end
        
        # Generate new VAPID keys
        vapid_keys = current_restaurant.generate_web_push_vapid_keys!
        
        render json: { 
          status: "success", 
          message: "VAPID keys generated successfully",
          public_key: vapid_keys[:public_key],
          private_key: vapid_keys[:private_key]
        }
      rescue => e
        render json: { 
          status: "error", 
          message: "Failed to generate VAPID keys: #{e.message}" 
        }, status: :internal_server_error
      end
    end
  end
end
```

## Database Schema

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_push_subscriptions.rb
class CreatePushSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :push_subscriptions do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :endpoint, null: false
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false
      t.boolean :active, default: true
      t.string :user_agent
      
      t.timestamps
    end
    
    add_index :push_subscriptions, [:restaurant_id, :endpoint], unique: true
  end
end
```

## Routes

```ruby
# config/routes.rb (web push related routes)
Rails.application.routes.draw do
  # Web Push Notifications
  resources :push_subscriptions, only: [:index, :create, :destroy] do
    collection do
      post :unsubscribe
      get :vapid_public_key
    end
  end
  
  namespace :admin do
    # System utilities
    post "generate_web_push_keys", to: "system#generate_web_push_keys"
  end
end
```

## Testing

You can test the Web Push notifications by:

1. Generating VAPID keys for a restaurant
2. Creating a subscription
3. Sending a test notification

```ruby
# Generate VAPID keys
restaurant = Restaurant.find(1)
vapid_keys = restaurant.generate_web_push_vapid_keys!

# Send a test notification
payload = {
  title: "Test Notification",
  body: "This is a test notification",
  icon: "/icons/icon-192.png"
}

restaurant.send_web_push_notification(payload)
```

## Resources

- [Web Push Protocol](https://tools.ietf.org/html/rfc8030)
- [Webpush Gem Documentation](https://github.com/zaru/webpush)
- [VAPID Protocol](https://tools.ietf.org/html/rfc8292)
