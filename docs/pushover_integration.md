# Pushover Integration

This document describes the integration of Pushover notifications into the Hafaloha backend application.

## Overview

Pushover is a service that makes it easy to get real-time notifications on your Android, iPhone, iPad, and Desktop devices. The Hafaloha application integrates with Pushover to send notifications to restaurant staff when new orders are placed, ensuring they're immediately aware of incoming orders even when not actively monitoring the admin dashboard.

## Architecture

The Pushover integration consists of several components:

1. **Restaurant Model**: Contains methods to check if Pushover is enabled and to send notifications
2. **SendPushoverNotificationJob**: Background job for asynchronous notification delivery
3. **PushoverClient**: Service class that handles the actual API communication
4. **Admin Settings**: JSONB field in the Restaurant model that stores Pushover configuration

## Restaurant Model Methods

```ruby
# app/models/restaurant.rb

def pushover_enabled?
  admin_settings&.dig("notification_channels", "orders", "pushover") == true && 
    (admin_settings&.dig("pushover", "user_key").present? || admin_settings&.dig("pushover", "group_key").present?)
end

def pushover_recipient_key
  admin_settings&.dig("pushover", "group_key").presence || admin_settings&.dig("pushover", "user_key")
end

def send_pushover_notification(message, title = nil, options = {})
  return false unless pushover_enabled?
  
  SendPushoverNotificationJob.perform_later(
    id, # restaurant_id
    message,
    title: title || name,
    priority: options[:priority] || 0,
    sound: options[:sound],
    url: options[:url],
    url_title: options[:url_title]
  )
  
  true
end
```

## Background Job

```ruby
# app/jobs/send_pushover_notification_job.rb

class SendPushoverNotificationJob < ApplicationJob
  queue_as :notifications

  # Retry failed jobs with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 5

  def perform(restaurant_id, message, title: nil, priority: 0, sound: nil, url: nil, url_title: nil)
    # Find the restaurant
    restaurant = Restaurant.find_by(id: restaurant_id)
    
    # Return if restaurant not found or no Pushover keys are set
    return unless restaurant && restaurant.pushover_enabled?
    
    # Get the user key from the restaurant
    user_key = restaurant.pushover_recipient_key
    return unless user_key.present?
    
    # Send the notification
    PushoverClient.send_notification(
      user_key: user_key,
      message: message,
      title: title,
      priority: priority,
      app_token: restaurant.admin_settings&.dig("pushover", "app_token"),
      sound: sound,
      url: url,
      url_title: url_title
    )
  end
end
```

## Pushover Client Service

```ruby
# app/services/pushover_client.rb

class PushoverClient
  include HTTParty
  base_uri 'https://api.pushover.net/1'
  
  # Default app token used if restaurant doesn't provide their own
  DEFAULT_APP_TOKEN = ENV['PUSHOVER_APP_TOKEN']
  
  def self.send_notification(user_key:, message:, title: nil, priority: 0, app_token: nil, sound: nil, url: nil, url_title: nil)
    # Use provided app token or fall back to default
    token = app_token.presence || DEFAULT_APP_TOKEN
    
    # Build the request payload
    payload = {
      token: token,
      user: user_key,
      message: message,
      priority: priority
    }
    
    # Add optional parameters if provided
    payload[:title] = title if title.present?
    payload[:sound] = sound if sound.present?
    payload[:url] = url if url.present?
    payload[:url_title] = url_title if url_title.present?
    
    # For emergency priority (2), require retry and expire parameters
    if priority == 2
      payload[:retry] = 60 unless payload[:retry].present?
      payload[:expire] = 3600 unless payload[:expire].present?
    end
    
    # Send the request to Pushover API
    response = post('/messages.json', body: payload)
    
    # Check if the request was successful
    if response.success? && response.parsed_response['status'] == 1
      Rails.logger.info("Pushover notification sent successfully to #{user_key}")
      true
    else
      Rails.logger.error("Failed to send Pushover notification: #{response.parsed_response}")
      false
    end
  end
  
  def self.validate_user(user_key:, app_token: nil)
    # Use provided app token or fall back to default
    token = app_token.presence || DEFAULT_APP_TOKEN
    
    # Build the request payload
    payload = {
      token: token,
      user: user_key
    }
    
    # Send the request to Pushover API
    response = post('/users/validate.json', body: payload)
    
    # Check if the user is valid
    if response.success? && response.parsed_response['status'] == 1
      Rails.logger.info("Pushover user #{user_key} is valid")
      true
    else
      Rails.logger.error("Invalid Pushover user: #{response.parsed_response}")
      false
    end
  end
end
```

## Order Notification

When a new order is created, a Pushover notification is sent to the restaurant staff:

```ruby
# app/models/order.rb

after_create :notify_pushover

def notify_pushover
  return if Rails.env.test?
  
  # Format the order items for the notification
  food_item_lines = items.map do |item|
    "#{item['name']} (x#{item['quantity']}): $#{'%.2f' % item['price']}"
  end.join(", ")
  
  # Create a concise message for the notification
  message = "New order ##{id} - $#{'%.2f' % total.to_f}"
  
  # Add more details in the extended message
  extended_message = <<~MSG
    New order ##{id} received!
    
    Items: #{food_item_lines}
    
    Total: $#{'%.2f' % total.to_f}
    Status: #{status}
    
    #{contact_name ? "Customer: #{contact_name}" : ""}
    #{special_instructions.present? ? "Instructions: #{special_instructions}" : ""}
  MSG
  
  # Enqueue the Pushover notification job
  SendPushoverNotificationJob.perform_later(
    restaurant_id,
    extended_message,
    title: message,
    priority: 1, # High priority to bypass quiet hours
    sound: "incoming" # Use the "incoming" sound for new orders
  )
end
```

## Admin Controller Endpoints

The admin controller provides endpoints for validating Pushover keys and sending test notifications:

```ruby
# app/controllers/admin/system_controller.rb

def validate_pushover_key
  user_key = params[:user_key]
  app_token = params[:app_token]
  
  if user_key.blank?
    render json: { error: "User key is required" }, status: :bad_request
    return
  end
  
  valid = PushoverClient.validate_user(user_key: user_key, app_token: app_token)
  
  render json: { valid: valid }
end

def test_pushover
  user_key = params[:user_key]
  message = params[:message] || "This is a test notification from Hafaloha"
  title = params[:title] || "Test Notification"
  priority = params[:priority] || 0
  sound = params[:sound] || "pushover"
  app_token = params[:app_token]
  
  if user_key.blank?
    render json: { error: "User key is required" }, status: :bad_request
    return
  end
  
  success = PushoverClient.send_notification(
    user_key: user_key,
    message: message,
    title: title,
    priority: priority,
    sound: sound,
    app_token: app_token
  )
  
  if success
    render json: { status: "success", message: "Test notification sent successfully" }
  else
    render json: { status: "error", message: "Failed to send test notification" }
  end
end
```

## Configuration

### Environment Variables

- `PUSHOVER_APP_TOKEN`: Default application token used when restaurants don't provide their own

### Admin Settings Structure

Pushover settings are stored in the restaurant's `admin_settings` JSONB field:

```json
{
  "notification_channels": {
    "orders": {
      "pushover": true
    }
  },
  "pushover": {
    "user_key": "user_key_from_pushover_dashboard",
    "group_key": "optional_group_key",
    "app_token": "optional_custom_app_token"
  }
}
```

## Sidekiq Configuration

The Pushover notification job runs in the `notifications` queue, which needs to be configured in `config/sidekiq.yml`:

```yaml
:concurrency: 5
:queues:
  - default
  - mailers
  - sms
  - notifications
```

## Security Considerations

- Pushover user keys and application tokens are stored securely in the database
- All communication with the Pushover API is done over HTTPS
- The application uses a default application token, but restaurants can use their own for additional security

## Troubleshooting

- **Job Not Running**: Ensure the `notifications` queue is configured in `config/sidekiq.yml`
- **Notification Not Sent**: Check if `pushover_enabled?` returns true for the restaurant
- **API Errors**: Check the Rails logs for detailed error messages from the Pushover API
