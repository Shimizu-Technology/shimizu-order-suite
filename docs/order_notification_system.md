# Order Notification System - Backend Documentation

## Overview

The Order Notification System is a critical component of the Hafaloha application that ensures staff members are promptly notified about new orders and inventory changes. This document outlines the backend implementation of the notification system, including its core components, data flow, and integration with other parts of the application.

## Core Components

### 1. Notification Model

The `Notification` model is the central entity that represents notifications in the system:

```ruby
class Notification < ApplicationRecord
  include Broadcastable
  apply_default_scope
  
  # Associations
  belongs_to :restaurant
  belongs_to :resource, polymorphic: true, optional: true
  belongs_to :acknowledged_by, class_name: "User", optional: true
  
  # Scopes
  scope :unacknowledged, -> { where(acknowledged: false) }
  scope :acknowledged, -> { where(acknowledged: true) }
  scope :by_type, ->(type) { where(notification_type: type) }
  # ...
end
```

Key attributes:
- `title`: Short description of the notification
- `body`: Detailed message
- `notification_type`: Type of notification (e.g., 'order', 'low_stock')
- `resource_type` and `resource_id`: Polymorphic association to the related resource
- `acknowledged`: Boolean indicating if the notification has been acknowledged
- `metadata`: JSON field containing additional context-specific information

### 2. Broadcastable Concern

The `Broadcastable` concern handles real-time broadcasting of notifications through WebSockets:

```ruby
module Broadcastable
  extend ActiveSupport::Concern
  
  # ...
  
  def broadcast_notification(options = {})
    restaurant_id = get_restaurant_id
    return unless restaurant_id.present?
    
    channel_name = "notification_channel_#{restaurant_id}"
    payload = {
      type: 'notification',
      notification: options[:destroyed] ? { id: id, destroyed: true } : self.as_json
    }
    
    ActionCable.server.broadcast(channel_name, payload)
  end
  
  # ...
end
```

### 3. NotificationsController

The `NotificationsController` provides API endpoints for managing notifications:

```ruby
class NotificationsController < ApplicationController
  # GET /notifications/unacknowledged
  def unacknowledged
    # Retrieve unacknowledged notifications with filtering options
  end
  
  # POST /notifications/:id/acknowledge
  def acknowledge
    # Mark a notification as acknowledged
  end
  
  # POST /notifications/acknowledge_all
  def acknowledge_all
    # Acknowledge all notifications matching parameters
  end
  
  # POST /notifications/:id/take_action
  def take_action
    # Take action on a notification (e.g., restock inventory)
  end
  
  # ...
end
```

### 4. Notification Channels

The notification system uses ActionCable channels to deliver real-time notifications:

- `NotificationChannel`: Handles subscription to notification events for a specific restaurant
- `OrderChannel`: Specifically for order-related notifications

## Data Flow

### Notification Creation

1. An event occurs (e.g., new order is placed, inventory falls below threshold)
2. A notification record is created in the database
3. The `after_save` callback in the `Broadcastable` concern triggers
4. The notification is broadcasted to the appropriate channel based on its type
5. Connected clients receive the notification in real-time

### Notification Acknowledgment

1. A user acknowledges a notification via the frontend
2. The frontend calls the `acknowledge` endpoint
3. The notification is marked as acknowledged in the database
4. The update triggers another broadcast to inform all clients
5. All connected clients update their UI to reflect the acknowledgment

## Deduplication Mechanism

The backend implements notification deduplication through several mechanisms:

1. **Database Constraints**: Unique constraints prevent duplicate notifications for the same event
2. **Conditional Creation**: Notifications are only created when specific conditions are met
3. **Scoped Queries**: The API endpoints return notifications scoped to the user's restaurant

## Integration with Other Components

### Orders System

When a new order is created:
```ruby
def after_create_notification
  Notification.create!(
    title: "New Order ##{number}",
    body: "A new order has been placed by #{customer_name}",
    notification_type: "order",
    resource_type: "Order",
    resource_id: id,
    restaurant_id: restaurant_id,
    metadata: {
      order_id: id,
      customer_name: customer_name,
      total: total_amount
    }
  )
end
```

### Inventory System

When inventory falls below threshold:
```ruby
def check_low_stock
  if enable_stock_tracking && stock_quantity <= low_stock_threshold
    create_low_stock_notification
  end
end

def create_low_stock_notification
  # Create notification only if one doesn't already exist
  existing = Notification.unacknowledged
                        .by_type("low_stock")
                        .where(resource_type: self.class.name, resource_id: id)
                        .exists?
  
  return if existing
  
  Notification.create!(
    title: "Low Stock Alert",
    body: "#{name} is running low on stock (#{stock_quantity} remaining)",
    notification_type: "low_stock",
    resource_type: self.class.name,
    resource_id: id,
    restaurant_id: restaurant_id,
    metadata: {
      item_id: id,
      stock_quantity: stock_quantity,
      threshold: low_stock_threshold
    }
  )
end
```

## Best Practices

1. **Restaurant Isolation**: All notifications are scoped to a specific restaurant
2. **Efficient Queries**: Use scopes to efficiently retrieve notifications
3. **Conditional Broadcasting**: Only broadcast changes when relevant attributes change
4. **Error Handling**: Implement robust error handling for notification creation and delivery
5. **Cleanup**: Implement periodic cleanup of old acknowledged notifications

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/notifications/unacknowledged` | GET | Retrieve unacknowledged notifications |
| `/notifications/:id/acknowledge` | POST | Acknowledge a specific notification |
| `/notifications/acknowledge_all` | POST | Acknowledge all notifications matching filters |
| `/notifications/:id/take_action` | POST | Take action on a notification |
| `/notifications/count` | GET | Get count of unacknowledged notifications |
| `/notifications/stats` | GET | Get notification statistics |

## Troubleshooting

### Common Issues

1. **Missing Notifications**
   - Check that the notification creation logic is being triggered
   - Verify that the restaurant_id is correctly set
   - Ensure WebSocket connections are established

2. **Duplicate Notifications**
   - Check for race conditions in notification creation
   - Verify deduplication logic is working correctly
   - Ensure clients are properly handling notification updates

3. **Delayed Notifications**
   - Check ActionCable server configuration
   - Verify Redis is functioning correctly (if used)
   - Check network latency between server and clients
