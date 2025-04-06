# app/services/websocket_broadcast_service.rb

class WebsocketBroadcastService
  # Broadcast a new order to the appropriate restaurant channel
  def self.broadcast_new_order(order)
    return unless order.restaurant_id.present?
    
    # Get the order as JSON with all necessary fields for filtering
    order_json = order.as_json(
      include: [],
      methods: [:created_by_staff_id, :created_by_user_id, :is_staff_order]
    )
    
    # Add explicit staff information for frontend filtering
    staff_info = {
      created_by_staff_id: order.created_by_staff_id,
      created_by_user_id: order.created_by_user_id,
      is_staff_order: order.is_staff_order
    }
    
    # Ensure these fields are included in the broadcast
    order_json.merge!(staff_info)
    
    # Log the staff information for debugging
    Rails.logger.info("Order #{order.id} staff info: created_by_staff=#{order.created_by_staff_id}, created_by_user=#{order.created_by_user_id}, is_staff=#{order.is_staff_order}")
    
    ActionCable.server.broadcast(
      "order_channel_#{order.restaurant_id}",
      {
        type: 'new_order',
        order: order_json,
        staff_info: staff_info # Include staff info separately for easier access
      }
    )
    
    Rails.logger.info("Broadcasted new order #{order.id} to order_channel_#{order.restaurant_id}")
  end
  
  # Broadcast an order update to the appropriate restaurant channel
  def self.broadcast_order_update(order)
    return unless order.restaurant_id.present?
    
    # Get the order as JSON with all necessary fields for filtering
    order_json = order.as_json(
      include: [],
      methods: [:created_by_staff_id, :created_by_user_id, :is_staff_order]
    )
    
    # Add explicit staff information for frontend filtering
    staff_info = {
      created_by_staff_id: order.created_by_staff_id,
      created_by_user_id: order.created_by_user_id,
      is_staff_order: order.is_staff_order
    }
    
    # Ensure these fields are included in the broadcast
    order_json.merge!(staff_info)
    
    # Log the staff information for debugging
    Rails.logger.info("Order update #{order.id} staff info: created_by_staff=#{order.created_by_staff_id}, created_by_user=#{order.created_by_user_id}, is_staff=#{order.is_staff_order}")
    
    ActionCable.server.broadcast(
      "order_channel_#{order.restaurant_id}",
      {
        type: 'order_updated',
        order: order_json,
        staff_info: staff_info # Include staff info separately for easier access
      }
    )
    
    Rails.logger.info("Broadcasted order update #{order.id} to order_channel_#{order.restaurant_id}")
  end
  
  # Broadcast a low stock notification to the appropriate restaurant channel
  def self.broadcast_low_stock(item)
    # Get restaurant_id based on the item type
    restaurant_id = if item.respond_to?(:restaurant_id) && item.restaurant_id.present?
      # Direct restaurant_id field
      item.restaurant_id
    elsif item.respond_to?(:restaurant) && item.restaurant.present?
      # Direct restaurant association
      item.restaurant.id
    elsif item.respond_to?(:menu) && item.menu.present? && item.menu.respond_to?(:restaurant_id)
      # MenuItem case - access through menu
      item.menu.restaurant_id
    else
      Rails.logger.error("[WebsocketBroadcastService] Cannot determine restaurant_id for #{item.class.name} ##{item.id}")
      return
    end
    
    return unless restaurant_id.present?
    
    ActionCable.server.broadcast(
      "inventory_channel_#{restaurant_id}",
      {
        type: 'low_stock',
        item: item.as_json
      }
    )
    
    Rails.logger.info("Broadcasted low stock alert for item #{item.id} to inventory_channel_#{restaurant_id}")
  end
end