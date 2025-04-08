# WebSocket Implementation for Shimizu Order Suite

This document provides a comprehensive guide to the WebSocket implementation in the Shimizu Order Suite application, which enables real-time updates for orders and inventory. WebSockets are now fully functional and provide real-time notifications for new orders and inventory changes.

## Overview

The WebSocket implementation replaces the previous polling-based approach for real-time updates, providing several benefits:

- **Real-time Updates**: Instant notification of new orders and inventory changes
- **Reduced Server Load**: Fewer HTTP requests and overhead
- **Lower Latency**: No waiting for the next polling interval
- **Reduced Network Traffic**: Only sending data when there are actual changes
- **Better User Experience**: Immediate updates for admins managing orders

## Architecture

The implementation follows a pub/sub (publish/subscribe) pattern:

1. **Backend (Rails)**: Uses Action Cable for WebSocket support
2. **Frontend (React)**: Uses a custom WebSocket service to manage connections

### Backend Components

- **Connection Authentication**: JWT-based authentication for WebSocket connections
- **Channels**: Separate channels for different notification types
- **Broadcasting Service**: Centralized service for broadcasting messages
- **Broadcastable Concern**: A reusable concern that models can include to gain broadcasting capabilities

### Frontend Components

- **WebSocket Service**: A TypeScript service that manages WebSocket connections, reconnection logic, and message handling
- **React Hook (useWebSocket)**: A custom React hook that provides easy integration with React components
- **Fallback Mechanism**: Automatically falls back to polling if WebSockets are unavailable or disconnected
- **Token Management**: Ensures proper authentication token handling for WebSocket connections

## Implementation Details

### Backend (Rails)

The backend uses Action Cable, which is Rails' built-in WebSocket framework. Action Cable integrates WebSockets with the rest of your Rails application, allowing for real-time features.

#### Inventory Management Integration

The WebSocket system is integrated with the inventory management system to provide real-time updates on stock levels. Key features include:

- **Damaged Item Tracking**: When items are marked as damaged, the system broadcasts updates to all connected clients without affecting stock quantities
- **Available Quantity Calculation**: Available inventory is calculated as `stock_quantity - damaged_quantity`
- **Low Stock Alerts**: Real-time alerts are sent when inventory falls below the defined threshold

#### Connection Authentication

WebSocket connections are authenticated using JWT tokens. The `Connection` class in `app/channels/application_cable/connection.rb` verifies the token and identifies the user and restaurant.

```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :restaurant_id

    def connect
      self.current_user = find_verified_user
      self.restaurant_id = current_user&.restaurant_id
    end

    private

    def find_verified_user
      # Extract token from params
      token = request.params[:token]
      return reject_unauthorized_connection unless token

      begin
        # Decode the JWT token
        decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')[0]
        user_id = decoded["user_id"]
        
        # Find the user
        user = User.find_by(id: user_id)
        
        # Check token expiration if exp is present
        if decoded["exp"].present? && Time.at(decoded["exp"]) < Time.current
          Rails.logger.error("WebSocket connection rejected: Token expired")
          return reject_unauthorized_connection
        end
        
        # Return the user or reject the connection
        if user
          user
        else
          Rails.logger.error("WebSocket connection rejected: User not found")
          reject_unauthorized_connection
        end
      rescue JWT::DecodeError => e
        Rails.logger.error("WebSocket connection rejected: JWT decode error - #{e.message}")
        reject_unauthorized_connection
      rescue => e
        Rails.logger.error("WebSocket connection rejected: #{e.message}")
        reject_unauthorized_connection
      end
    end
  end
end
```

#### Channels

Multiple channels are implemented for different notification types:

1. **OrderChannel**: For order-related events
2. **InventoryChannel**: For inventory-related events
3. **MenuChannel**: For menu and menu item updates
4. **NotificationChannel**: For system notifications
5. **CategoryChannel**: For category updates

Each channel streams from a restaurant-specific channel to ensure multi-tenancy.

```ruby
# app/channels/order_channel.rb
class OrderChannel < ApplicationCable::Channel
  def subscribed
    # Stream from a restaurant-specific channel
    if restaurant_id.present?
      stream_from "order_channel_#{restaurant_id}"
      Rails.logger.info("User #{current_user.id} subscribed to order_channel_#{restaurant_id}")
    else
      # Reject the subscription if no restaurant_id is available
      Rails.logger.error("Subscription rejected: No restaurant_id available")
      reject
    end
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
    Rails.logger.info("User #{current_user&.id} unsubscribed from order channel")
  end
end
```

```ruby
# app/channels/inventory_channel.rb
class InventoryChannel < ApplicationCable::Channel
  def subscribed
    # Stream from a restaurant-specific channel
    if restaurant_id.present?
      stream_from "inventory_channel_#{restaurant_id}"
      Rails.logger.info("User #{current_user.id} subscribed to inventory_channel_#{restaurant_id}")
    else
      # Reject the subscription if no restaurant_id is available
      Rails.logger.error("Subscription rejected: No restaurant_id available")
      reject
    end
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
    Rails.logger.info("User #{current_user&.id} unsubscribed from inventory channel")
  end
end
```

#### Broadcasting Service

A centralized service handles broadcasting messages to the appropriate channels:

```ruby
# app/services/websocket_broadcast_service.rb
class WebsocketBroadcastService
  # Broadcast a new order to the appropriate restaurant channel
  def self.broadcast_new_order(order)
    return unless order.restaurant_id.present?
    
    # Get the order as JSON
    order_json = order.as_json
    
    ActionCable.server.broadcast(
      "order_channel_#{order.restaurant_id}",
      {
        type: 'new_order',
        order: order_json
      }
    )
    
    Rails.logger.info("Broadcasted new order #{order.id} to order_channel_#{order.restaurant_id}")
  end
  
  # Broadcast an order update to the appropriate restaurant channel
  def self.broadcast_order_update(order)
    return unless order.restaurant_id.present?
    
    # Get the order as JSON
    order_json = order.as_json
    
    ActionCable.server.broadcast(
      "order_channel_#{order.restaurant_id}",
      {
        type: 'order_updated',
        order: order_json
      }
    )
    
    Rails.logger.info("Broadcasted order update #{order.id} to order_channel_#{order.restaurant_id}")
  end
  
  # Broadcast a low stock notification to the appropriate restaurant channel
  def self.broadcast_low_stock(item)
    # Get restaurant_id based on the item type
    restaurant_id = if item.respond_to?(:restaurant_id) && item.restaurant_id.present?
      item.restaurant_id
    elsif item.respond_to?(:restaurant) && item.restaurant.present?
      item.restaurant.id
    elsif item.respond_to?(:menu) && item.menu.present? && item.menu.respond_to?(:restaurant_id)
      item.menu.restaurant_id
    else
      Rails.logger.error("[WebsocketBroadcastService] Cannot determine restaurant_id for #{item.class.name} ##{item.id}")
      return
    end
    
    ActionCable.server.broadcast(
      "inventory_channel_#{restaurant_id}",
      {
        type: 'low_stock',
        item: item.as_json(methods: [:available_quantity])
      }
    )
    
    Rails.logger.info("Broadcasted low stock alert for item #{item.id} to inventory_channel_#{restaurant_id}")
  end
end
```

### Frontend (React)

#### WebSocket Service

A singleton service manages WebSocket connections and message handling:

```typescript
// src/shared/services/websocketService.ts
class WebSocketService {
  private socket: WebSocket | null = null;
  private callbacks: WebSocketCallbacks = {};
  private reconnectAttempts: number = 0;
  private maxReconnectAttempts: number = 10;
  private reconnectTimeout: number = 1000; // ms
  private reconnectTimer: NodeJS.Timeout | null = null;
  private isConnecting: boolean = false;
  private restaurantId: string | null = null;
  private isActive: boolean = false;

  // Connect to WebSocket server
  public connect(restaurantId: string, callbacks: WebSocketCallbacks = {}): void {
    // Implementation details...
  }

  // Handle WebSocket events
  private handleOpen(): void { /* ... */ }
  private handleMessage(event: MessageEvent): void { /* ... */ }
  private handleClose(event: CloseEvent): void { /* ... */ }
  private handleError(error: any): void { /* ... */ }

  // Reconnection logic
  private attemptReconnect(): void { /* ... */ }

  // Channel subscriptions
  private subscribeToOrderChannel(): void { /* ... */ }
  private subscribeToInventoryChannel(): void { /* ... */ }

  // Disconnect from WebSocket server
  public disconnect(): void { /* ... */ }

  // Check connection status
  public isConnected(): boolean { /* ... */ }
}

// Create a singleton instance
export const websocketService = new WebSocketService();
```

#### React Hook

A custom hook provides easy integration with React components:

```typescript
// src/shared/hooks/useWebSocket.ts
export const useWebSocket = (options: UseWebSocketOptions = {}): UseWebSocketResult => {
  const { user } = useAuthStore();
  const [isConnected, setIsConnected] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  // Connect to WebSocket
  const connect = useCallback(() => { /* ... */ }, [/* dependencies */]);

  // Disconnect from WebSocket
  const disconnect = useCallback(() => { /* ... */ }, []);

  // Auto-connect when component mounts
  useEffect(() => { /* ... */ }, [/* dependencies */]);

  return {
    isConnected,
    error,
    connect,
    disconnect
  };
};
```

#### Integration with AdminDashboard

The AdminDashboard component uses the WebSocket hook to receive real-time updates:

```typescript
// src/ordering/components/admin/AdminDashboard.tsx
const { isConnected, error: wsError } = useWebSocket({
  autoConnect: USE_WEBSOCKETS && !!user && (user.role === 'admin' || user.role === 'super_admin'),
  onNewOrder: handleNewOrder,
  onLowStock: handleLowStock,
  onConnected: () => console.log('[WebSocket] Connected successfully'),
  onDisconnected: () => console.log('[WebSocket] Disconnected'),
  onError: (err) => console.error('[WebSocket] Error:', err)
});
```

## Testing

### Test Script

A test script is provided to broadcast test messages to WebSocket channels:

```ruby
# script/test_websocket.rb
#!/usr/bin/env ruby
# Usage: rails runner script/test_websocket.rb [restaurant_id]

# Get restaurant_id from command line or default to 1
restaurant_id = ARGV[0] || 1

# Create test data...

# Broadcast test order
ActionCable.server.broadcast(
  "order_channel_#{restaurant_id}",
  {
    type: 'new_order',
    order: test_order
  }
)

# Broadcast test inventory item
ActionCable.server.broadcast(
  "inventory_channel_#{restaurant_id}",
  {
    type: 'low_stock',
    item: test_item
  }
)
```

### Test Page

A test HTML page is provided to verify WebSocket connections:

```html
<!-- public/websocket_test.html -->
<!DOCTYPE html>
<html lang="en">
<head>
    <title>WebSocket Test</title>
    <!-- ... -->
</head>
<body>
    <!-- UI for testing WebSocket connections -->
    <script>
        // JavaScript for WebSocket testing
    </script>
</body>
</html>
```

## How to Test

1. **Start the Rails server**:
   ```
   cd shimizu-order-suite
   rails server
   ```

2. **Open the test page**:
   Navigate to http://localhost:3000/websocket_test.html

3. **Get a valid JWT token**:
   Log in to the application in another tab to get a valid JWT token

4. **Connect to WebSocket**:
   Paste the token in the test page and click "Connect"

5. **Send test messages**:
   ```
   cd shimizu-order-suite
   rails runner script/test_websocket.rb [restaurant_id]
   ```

6. **Verify in the admin dashboard**:
   Log in to the admin dashboard and verify that notifications appear without refreshing

## Troubleshooting

### Common Issues

1. **Connection Rejected**:
   - Check that the JWT token is valid and not expired
   - Verify that the user has access to the specified restaurant

2. **No Messages Received**:
   - Check that you're subscribed to the correct channels
   - Verify that messages are being broadcast to the correct channel

3. **Connection Closing Unexpectedly**:
   - Check the server logs for any errors
   - Verify that Redis is running if using the Redis adapter

### Debugging

1. **Check Rails Logs**:
   Look for WebSocket-related log messages in the Rails server logs

2. **Browser Console**:
   Check the browser console for WebSocket-related errors

3. **Network Tab**:
   Inspect WebSocket frames in the browser's network tab

## Deployment Considerations

### Redis Configuration

In production, Action Cable uses Redis as the adapter. Make sure Redis is properly configured:

```yaml
# config/cable.yml
production:
  adapter: redis
  url: <%= ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" } %>
  channel_prefix: hafaloha_api_production
```

### Load Balancing

If using multiple application servers, ensure that WebSocket connections are properly load balanced:

- Use sticky sessions to route WebSocket connections to the same server
- Configure the load balancer to support WebSocket connections

### Scaling

WebSockets maintain persistent connections, so plan your infrastructure accordingly:

- Monitor the number of concurrent connections
- Scale horizontally if needed
- Consider using a dedicated WebSocket server for high-traffic applications

## Future Enhancements

1. **Additional Notification Types**:
   - Customer feedback notifications
   - Payment issue notifications
   - System status notifications

2. **Client-to-Server Messages**:
   - Real-time order updates from the admin dashboard
   - Interactive features like chat support

3. **Analytics**:
   - Track WebSocket usage and performance
   - Monitor connection statistics

## Current Issues and Future Work

### Known Issues

1. **Connection Stability**: WebSocket connections are being established successfully but are immediately closed with code 1000 (normal closure). This might be due to:
  - Issues with the Action Cable configuration
  - Problems with the Redis adapter
  - Middleware or proxy configuration issues

2. **Reconnection Loop**: The current implementation attempts to reconnect when connections are closed, but this can lead to a reconnection loop if the underlying issue isn't resolved.

3. **Notification Store Error**: There's an error in the notification store: "API returned non-array notifications: object" which might be related to the WebSocket implementation.

### Recent Updates and Fixes

#### Inventory Management System

1. **Damaged Item Handling**: Updated the `mark_as_damaged` method in the MenuItem model to only increase the damaged quantity without reducing the stock quantity. This ensures accurate tracking of both total and damaged inventory.

```ruby
def mark_as_damaged(quantity = 1)
  return false unless enable_stock_tracking
  
  # Only update damaged_quantity, don't reduce stock_quantity
  update(damaged_quantity: damaged_quantity + quantity)
  
  # Broadcast low stock if available quantity is below threshold
  broadcast_low_stock if available_quantity <= low_stock_threshold
  
  true
end
```

2. **Available Quantity Calculation**: Modified the `available_quantity` method to calculate available inventory as `stock_quantity - damaged_quantity`.

```ruby
def available_quantity
  return nil unless enable_stock_tracking
  stock_quantity - damaged_quantity
end
```

3. **WebSocket Broadcasting**: Fixed the `WebsocketBroadcastService.broadcast_low_stock` method to correctly retrieve the restaurant ID from the MenuItem model using a more robust approach that works with different model structures.

4. **Order Refund Processing**: Fixed the `update` method in the OrdersController to ensure the order variable is defined before use, preventing errors during order updates.

#### Menu Item Availability

Fixed an issue with the menu item's available days not being cleared when all days are deselected in the UI. The controller now properly handles the case when no days are selected by setting `available_days` to an empty array, making the item available every day.

### Troubleshooting and Resolved Issues

### Connection Issues

We resolved several key issues with the WebSocket implementation:

1. **Authentication Token Format**: The frontend was storing the token in localStorage under `token`, but the WebSocket connection was looking for `auth_token`. We updated the `authStore` to store the token under both keys.

2. **Connection Disconnect Error**: Fixed an error in the `disconnect` method of the Connection class where it was incorrectly calling `super` when there was no parent method to call.

3. **EventMachine Error**: Resolved an issue with the EventMachine timer by using the ActionCable reactor instead of directly calling EventMachine.

4. **Nil Object Error**: Added nil checks for the `@connected_at` timestamp to prevent errors when calculating uptime.

### Common Issues and Solutions

1. **Connection Authentication Failures**:
   - Check that the token is being properly passed in the WebSocket URL
   - Verify the token format and expiration
   - Ensure the user has the correct permissions

2. **Message Not Received**:
   - Verify the channel subscription is active
   - Check that the broadcast is targeting the correct channel
   - Ensure the message format matches what the client expects

3. **Connection Drops**:
   - Implement reconnection logic with exponential backoff
   - Check for network issues or proxies that might be terminating idle connections
   - Ensure Redis is properly configured for Action Cable

2. **Implement Heartbeat Mechanism**: Add a heartbeat mechanism to keep connections alive.
  - Send periodic ping messages from the server
  - Respond with pong messages from the client

3. **Improve Error Handling**: Enhance error handling and logging to better diagnose issues.
  - Add more detailed logging on both client and server
  - Implement better error recovery strategies

4. **Test in Production Environment**: Verify that the implementation works in a production-like environment.
  - Test with multiple concurrent users
  - Monitor connection stability over time
  - Measure performance impact

Until these issues are resolved, the application will continue to use the polling mechanism for real-time updates.

## Conclusion

While the WebSocket implementation has the potential to provide a significant improvement over the polling-based approach, it is currently disabled due to connection stability issues. The architecture is designed to be scalable, maintainable, and secure, with proper authentication and multi-tenancy support, but additional work is needed to resolve the current issues.

In the meantime, the application continues to use the polling mechanism for real-time updates, which provides a reliable fallback solution. Once the WebSocket implementation is stable, it will offer real-time updates with lower latency and reduced server load.