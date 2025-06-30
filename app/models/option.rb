# app/models/option.rb
class Option < ApplicationRecord
  # Define associations first
  belongs_to :option_group
  has_many :option_stock_audits, dependent: :destroy
  
  # Then include concerns that depend on associations
  include IndirectTenantScoped
  include Broadcastable
  
  # Define the path to restaurant for tenant isolation
  tenant_path through: [:option_group, :menu_item, :menu], foreign_key: 'restaurant_id'

  # Configure which attributes should trigger broadcasts
  broadcasts_on :stock_quantity, :damaged_quantity, :is_available
  
  # Default scope to order by position
  default_scope { order(position: :asc) }

  validates :name, presence: true
  validates :additional_price, numericality: { greater_than_or_equal_to: 0.0 }
  validates :is_preselected, inclusion: { in: [true, false] }
  validates :is_available, inclusion: { in: [true, false] }
  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: false
  validates :damaged_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: false
  validate :damaged_quantity_not_greater_than_stock
  validate :option_stock_change_maintains_synchronization, if: :inventory_tracking_enabled?

  # RT-004: Add callback to check for low stock notifications after save
  after_save :check_for_low_stock_notification

  # Custom validation to ensure damaged quantity doesn't exceed stock quantity
  def damaged_quantity_not_greater_than_stock
    if stock_quantity.present? && damaged_quantity.present? && damaged_quantity > stock_quantity
      errors.add(:damaged_quantity, "cannot be greater than stock quantity")
    end
  end

  # Validation: Ensure option stock changes maintain synchronization with menu item
  def option_stock_change_maintains_synchronization
    return unless stock_quantity_changed? || new_record?
    return unless option_group&.menu_item&.enable_stock_tracking
    
    menu_item = option_group.menu_item
    return unless menu_item.stock_quantity.present?
    
    # Calculate what the total option stock would be after this change
    other_options_stock = option_group.options.where.not(id: id).sum(:stock_quantity)
    projected_total = other_options_stock + (stock_quantity || 0)
    menu_item_stock = menu_item.stock_quantity.to_i
    
    if projected_total != menu_item_stock
      errors.add(:stock_quantity, "would cause option totals (#{projected_total}) to not match menu item stock (#{menu_item_stock})")
    end
  end

  # Note: with_restaurant_scope is now provided by IndirectTenantScoped

  # Instead of overriding as_json, we provide a method that returns a float.
  # The controller uses `methods: [:additional_price_float]` to include it.
  def additional_price_float
    additional_price.to_f
  end
  
  # Check if this option has inventory tracking enabled through its option group
  def inventory_tracking_enabled?
    option_group&.inventory_tracking_enabled? || false
  end

  # Get available stock for this option (stock - damaged)
  def available_stock
    return 0 unless inventory_tracking_enabled?
    [stock_quantity - damaged_quantity, 0].max
  end

  # Check if option is in stock (has available stock)
  def in_stock?
    return true unless inventory_tracking_enabled?
    available_stock > 0
  end

  # Check if option is out of stock
  def out_of_stock?
    inventory_tracking_enabled? && available_stock <= 0
  end

  # Check if option is low stock (you can customize the threshold)
  def low_stock?(threshold = 5)
    return false unless inventory_tracking_enabled?
    available_stock <= threshold && available_stock > 0
  end

  # RT-004: Get the low stock threshold for this option
  def low_stock_threshold
    # Use the menu item's low stock threshold as default, or 5 if not set
    option_group&.menu_item&.low_stock_threshold || 5
  end

  # RT-004: Check if this option just went low stock (for notification purposes)
  def just_went_low_stock?
    return false unless inventory_tracking_enabled?
    return false unless saved_change_to_stock_quantity? || saved_change_to_damaged_quantity?
    
    # Check if we just crossed the low stock threshold
    current_available = available_stock
    
    # Calculate previous available stock
    previous_stock = stock_quantity_before_last_save || stock_quantity
    previous_damaged = damaged_quantity_before_last_save || damaged_quantity
    previous_available = [previous_stock - previous_damaged, 0].max
    
    # Return true if we went from above threshold to at or below threshold
    previous_available > low_stock_threshold && current_available <= low_stock_threshold && current_available > 0
  end

  # RT-004: Check if this option just went out of stock (for notification purposes)
  def just_went_out_of_stock?
    return false unless inventory_tracking_enabled?
    return false unless saved_change_to_stock_quantity? || saved_change_to_damaged_quantity?
    
    # Check if we just went to zero available stock
    current_available = available_stock
    
    # Calculate previous available stock
    previous_stock = stock_quantity_before_last_save || stock_quantity
    previous_damaged = damaged_quantity_before_last_save || damaged_quantity
    previous_available = [previous_stock - previous_damaged, 0].max
    
    # Return true if we went from having stock to having no stock
    previous_available > 0 && current_available <= 0
  end

  # Reduce stock by specified quantity (used during order processing)
  def reduce_stock!(quantity)
    return true unless inventory_tracking_enabled?
    
    if available_stock >= quantity
      self.stock_quantity -= quantity
      save!
      true
    else
      false
    end
  end

  # Increase stock by specified quantity (used during restocking or refunds)
  def increase_stock!(quantity)
    return true unless inventory_tracking_enabled?
    
    self.stock_quantity += quantity
    save!
    true
  end

  # Mark quantity as damaged
  def mark_damaged!(quantity)
    return true unless inventory_tracking_enabled?
    
    if stock_quantity >= (damaged_quantity + quantity)
      self.damaged_quantity += quantity
      save!
      true
    else
      false
    end
  end

  # Only increment damaged quantity without changing available quantity (for order edits/refunds)
  def increment_damaged_only(quantity, reason, user)
    return false unless inventory_tracking_enabled?

    # Add debug logging
    Rails.logger.info("INVENTORY DEBUG: Before increment_damaged_only - Option #{id} (#{name}) - Stock: #{stock_quantity}, Damaged: #{damaged_quantity}, Available: #{available_stock}")

    transaction do
      # Create audit record for damaged items
      OptionStockAudit.create_damaged_record(self, quantity, reason, user)

      # Update the damaged quantity
      previous_damaged = self.damaged_quantity || 0

      # IMPORTANT: Also increment the stock quantity by the same amount
      # This ensures that available_stock (stock - damaged) remains the same
      previous_stock = self.stock_quantity || 0

      # Update both quantities
      self.update!(
        damaged_quantity: previous_damaged + quantity.to_i,
        stock_quantity: previous_stock + quantity.to_i
      )

      # Create a stock adjustment audit record to track the stock increase
      OptionStockAudit.create_stock_record(
        self,
        previous_stock + quantity.to_i,
        "adjustment",
        "Stock adjusted to match damaged items from order",
        user
      )

      # Log after update
      Rails.logger.info("INVENTORY DEBUG: After increment_damaged_only - Option #{id} (#{name}) - Stock: #{stock_quantity}, Damaged: #{damaged_quantity}, Available: #{available_stock}")

      true
    end
  rescue => e
    Rails.logger.error("Failed to mark option as damaged: #{e.message}")
    false
  end
  
  # Override as_json to include the is_available field, position, and inventory info
  def as_json(options = {})
    super(options).tap do |json|
      json['additional_price_float'] = additional_price_float
      json['is_available'] = is_available
      json['position'] = position
      json['inventory_tracking_enabled'] = inventory_tracking_enabled?
      
      if inventory_tracking_enabled?
        json['stock_quantity'] = stock_quantity
        json['damaged_quantity'] = damaged_quantity
        json['available_stock'] = available_stock
        json['in_stock'] = in_stock?
        json['out_of_stock'] = out_of_stock?
        json['low_stock'] = low_stock?
        json['low_stock_threshold'] = low_stock_threshold
      end
    end
  end
  
  # Set default position when creating a new option
  before_create :set_default_position
  
  # Rebalance positions after deletion
  after_destroy :rebalance_positions
  
  private
  
  def set_default_position
    # If position is not set, set it to the last position in the group + 1
    if position.nil? || position.zero?
      max_position = option_group.options.maximum(:position) || 0
      self.position = max_position + 1
    end
  end
  
  def rebalance_positions
    # Get all remaining options in this group and rebalance their positions
    remaining_options = option_group.options.where.not(id: id).order(:position)
    
    # Update positions to ensure no gaps
    remaining_options.each_with_index do |option, index|
      option.update_column(:position, index + 1)
    end
  end

  # RT-004: Check for low stock notifications after save
  def check_for_low_stock_notification
    return unless inventory_tracking_enabled?
    return if Rails.env.test? # Skip notifications in test environment
    
    # Check if we should send a low stock notification
    if just_went_low_stock?
      create_low_stock_notification('low_stock')
    elsif just_went_out_of_stock?
      create_low_stock_notification('out_of_stock')
    end
  end

  # RT-004: Create a low stock notification for this option
  def create_low_stock_notification(notification_type)
    restaurant = option_group&.menu_item&.menu&.restaurant
    return unless restaurant
    
    menu_item = option_group.menu_item
    
    # Create the notification
    notification = Notification.create!(
      restaurant: restaurant,
      notification_type: notification_type,
      resource_type: 'Option',
      resource_id: id,
      title: "#{notification_type == 'low_stock' ? 'Low Stock' : 'Out of Stock'} Alert: #{menu_item.name} - #{name}",
      body: "Option '#{name}' for '#{menu_item.name}' is #{notification_type == 'low_stock' ? 'running low' : 'out of stock'}. Available: #{available_stock}",
      acknowledged: false
    )
    
    # RT-004: Also broadcast the specific notification type for real-time updates
    broadcast_option_notification(notification_type, restaurant.id, menu_item)
    
    Rails.logger.info("Created #{notification_type} notification for option #{id} (#{name}) - available stock: #{available_stock}")
    notification
  end
  
  private
  
  # RT-004: Broadcast option-specific notifications for real-time updates
  def broadcast_option_notification(notification_type, restaurant_id, menu_item)
    # Broadcast to notification channels that the frontend expects
    channel_names = [
      "notification_channel_#{restaurant_id}",
      "inventory_channel_#{restaurant_id}"
    ]
    
    # Create payload with option-specific data
    payload = {
      type: notification_type, # 'low_stock' or 'out_of_stock'
      option_id: id,
      option_name: name,
      option_group_id: option_group.id,
      option_group_name: option_group.name,
      menu_item_id: menu_item.id,
      menu_item_name: menu_item.name,
      available_stock: available_stock,
      stock_quantity: stock_quantity,
      damaged_quantity: damaged_quantity,
      threshold: low_stock_threshold,
      restaurant_id: restaurant_id,
      # Include notification details for frontend processing
      notification_type: notification_type,
      resource_type: 'Option',
      resource_id: id,
      title: "#{notification_type == 'low_stock' ? 'Low Stock' : 'Out of Stock'} Alert: #{menu_item.name} - #{name}",
      body: "Option '#{name}' for '#{menu_item.name}' is #{notification_type == 'low_stock' ? 'running low' : 'out of stock'}. Available: #{available_stock}",
      admin_path: "/admin/menu/items/#{menu_item.id}/inventory",
      acknowledged: false,
      created_at: Time.current.iso8601,
      updated_at: Time.current.iso8601
    }
    
    channel_names.each do |channel_name|
      Rails.logger.info("Broadcasting #{notification_type} notification to #{channel_name} - Option: #{id} (#{name})")
      ActionCable.server.broadcast(channel_name, payload)
    end
  end
end
