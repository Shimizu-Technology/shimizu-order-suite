# app/services/websocket_broadcast_service.rb

class WebsocketBroadcastService
  # Broadcast a new order to the appropriate restaurant channel
  def self.broadcast_new_order(order)
    return unless order.restaurant_id.present?
    
    # Skip broadcasting for staff-created orders if desired
    # return if order.staff_created?
    # Get the order as JSON
    order_json = order.as_json
    
    # Items are already included in the order JSON as a parsed array of hashes
    # No need to use include: :items which causes the error
    
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
    
    # Items are already included in the order JSON as a parsed array of hashes
    
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