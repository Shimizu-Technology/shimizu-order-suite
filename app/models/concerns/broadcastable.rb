module Broadcastable
  extend ActiveSupport::Concern

  class_methods do
    # Define which attributes should trigger broadcasts when changed
    def broadcasts_on(*attributes)
      @broadcast_attributes = attributes
    end

    def broadcast_attributes
      @broadcast_attributes || []
    end
  end

  included do
    after_save :broadcast_changes, if: :should_broadcast?
    after_destroy :broadcast_destruction
  end

  private

  def should_broadcast?
    return false unless get_restaurant_id.present?
    
    # Check if any of the broadcast attributes have changed
    return false if self.class.broadcast_attributes.empty?
    
    # Get the current transaction state if possible
    is_new = defined?(new_record_before_save?) ? new_record_before_save? : false
    
    self.class.broadcast_attributes.any? do |attr|
      changed_attributes.key?(attr.to_s) || 
      # Special case for newly created records
      (is_new && self.send(attr).present?)
    end
  end
  
  # Helper method to get restaurant_id from various model structures
  def get_restaurant_id
    # Try multiple approaches to get the restaurant_id
    restaurant_id = nil
    
    # First try direct restaurant_id field
    if self.respond_to?(:restaurant_id) && self.restaurant_id.present?
      restaurant_id = self.restaurant_id
    # Then try direct restaurant association
    elsif self.respond_to?(:restaurant) && self.restaurant.present?
      restaurant_id = self.restaurant.id
    # Then try through menu for MenuItem
    elsif self.class.name == 'MenuItem' && self.respond_to?(:menu) && self.menu.present?
      restaurant_id = self.menu.restaurant_id
    # Try to get from ActiveRecord::Base.current_restaurant if available
    elsif defined?(ActiveRecord::Base.current_restaurant) && ActiveRecord::Base.current_restaurant.present?
      restaurant_id = ActiveRecord::Base.current_restaurant.id
    end
    
    # Log if we couldn't determine the restaurant_id
    if restaurant_id.nil?
      Rails.logger.error("[Broadcastable] Cannot determine restaurant_id for #{self.class.name} ##{self.id}")
    end
    
    restaurant_id
  end

  def broadcast_changes
    # Check if this is a new record being saved (safely)
    is_new_record = defined?(new_record_before_save?) ? new_record_before_save? : false
    
    case self.class.name
    when 'MenuItem'
      broadcast_menu_item_update
      broadcast_inventory_update if inventory_changed?
    when 'Menu'
      broadcast_menu_update
    when 'Category'
      broadcast_category_update
    when 'Order'
      broadcast_order_update(new_record: is_new_record)
    when 'Notification'
      broadcast_notification
    end
  end

  def broadcast_destruction
    case self.class.name
    when 'MenuItem'
      broadcast_menu_item_update(destroyed: true)
    when 'Menu'
      broadcast_menu_update(destroyed: true)
    when 'Category'
      broadcast_category_update(destroyed: true)
    when 'Order'
      broadcast_order_update(destroyed: true)
    when 'Notification'
      broadcast_notification(destroyed: true)
    end
  end

  def inventory_changed?
    changed_attributes.keys.any? { |attr| ['stock_quantity', 'damaged_quantity', 'low_stock_threshold', 'enable_stock_tracking'].include?(attr) }
  end

  def broadcast_menu_item_update(options = {})
    restaurant_id = get_restaurant_id
    return unless restaurant_id.present?
    
    channel_name = "menu_channel_#{restaurant_id}"
    payload = {
      type: 'menu_item_update',
      menuItem: options[:destroyed] ? { id: id, destroyed: true } : self.as_json
    }
    
    Rails.logger.info("Broadcasting menu_item_update to #{channel_name} - Item: #{id}")
    ActionCable.server.broadcast(channel_name, payload)
  end

  def broadcast_inventory_update(options = {})
    restaurant_id = get_restaurant_id
    return unless restaurant_id.present?
    
    channel_name = "inventory_channel_#{restaurant_id}"
    payload = {
      type: 'inventory_update',
      item: options[:destroyed] ? { id: id, destroyed: true } : inventory_json
    }
    
    Rails.logger.info("Broadcasting inventory_update to #{channel_name} - Item: #{id}")
    ActionCable.server.broadcast(channel_name, payload)
  end

  def broadcast_menu_update(options = {})
    restaurant_id = get_restaurant_id
    return unless restaurant_id.present?
    
    channel_name = "menu_channel_#{restaurant_id}"
    payload = {
      type: 'menu_update',
      menu: options[:destroyed] ? { id: id, destroyed: true } : self.as_json
    }
    
    Rails.logger.info("Broadcasting menu_update to #{channel_name} - Menu: #{id}")
    ActionCable.server.broadcast(channel_name, payload)
  end

  def broadcast_category_update(options = {})
    restaurant_id = get_restaurant_id
    return unless restaurant_id.present?
    
    channel_name = "category_channel_#{restaurant_id}"
    payload = {
      type: 'category_update',
      category: options[:destroyed] ? { id: id, destroyed: true } : self.as_json
    }
    
    Rails.logger.info("Broadcasting category_update to #{channel_name} - Category: #{id}")
    ActionCable.server.broadcast(channel_name, payload)
  end

  def broadcast_order_update(options = {})
    restaurant_id = get_restaurant_id
    return unless restaurant_id.present?
    
    channel_name = "order_channel_#{restaurant_id}"
    
    # Determine the message type safely
    message_type = if options[:destroyed]
      'order_deleted'
    elsif options[:new_record]
      'new_order'
    else
      'order_updated'
    end
    
    payload = {
      type: message_type,
      order: options[:destroyed] ? { id: id, destroyed: true } : self.as_json
    }
    
    Rails.logger.info("Broadcasting #{payload[:type]} to #{channel_name} - Order: #{id}")
    ActionCable.server.broadcast(channel_name, payload)
  end

  def broadcast_notification(options = {})
    restaurant_id = get_restaurant_id
    return unless restaurant_id.present?
    
    channel_name = "notification_channel_#{restaurant_id}"
    payload = {
      type: 'notification',
      notification: options[:destroyed] ? { id: id, destroyed: true } : self.as_json
    }
    
    Rails.logger.info("Broadcasting notification to #{channel_name} - Notification: #{id}")
    ActionCable.server.broadcast(channel_name, payload)
  end
  
  def broadcast_restaurant_update(options = {})
    # For restaurant model, the restaurant_id is the id of the restaurant itself
    restaurant_id = self.id
    return unless restaurant_id.present?
    
    channel_name = "restaurant_channel_#{restaurant_id}"
    payload = {
      type: 'restaurant_update',
      restaurant: options[:destroyed] ? { id: id, destroyed: true } : self.as_json
    }
    
    Rails.logger.info("Broadcasting restaurant_update to #{channel_name} - Restaurant: #{id}")
    ActionCable.server.broadcast(channel_name, payload)
  end

  # Helper method for inventory updates
  def inventory_json
    {
      id: id,
      name: name,
      stock_quantity: stock_quantity,
      damaged_quantity: damaged_quantity,
      low_stock_threshold: low_stock_threshold,
      enable_stock_tracking: enable_stock_tracking,
      available_quantity: stock_quantity.to_i - damaged_quantity.to_i,
      updated_at: updated_at
    }
  end
end
