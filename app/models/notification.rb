class Notification < ApplicationRecord
  apply_default_scope

  # Define path to restaurant for tenant isolation
  belongs_to :restaurant
  
  # Polymorphic association for the resource this notification is about
  belongs_to :resource, polymorphic: true, optional: true
  
  # User who acknowledged the notification
  belongs_to :acknowledged_by, class_name: 'User', optional: true
  
  # Scopes for filtering
  scope :unacknowledged, -> { where(acknowledged: false) }
  scope :acknowledged, -> { where(acknowledged: true) }
  scope :by_type, ->(type) { where(notification_type: type) }
  scope :stock_alerts, -> { where(notification_type: 'low_stock') }
  scope :recent, -> { order(created_at: :desc) }
  scope :recent_first, -> { order(created_at: :desc) }
  
  # Override with_restaurant_scope for restaurant association
  def self.with_restaurant_scope
    if current_restaurant
      where(restaurant_id: current_restaurant.id)
    else
      all
    end
  end
  
  # Acknowledge this notification
  def acknowledge!(user = nil)
    update(
      acknowledged: true,
      acknowledged_at: Time.current,
      acknowledged_by: user
    )
  end
  
  # Get appropriate icon based on notification type
  def icon_class
    case notification_type
    when 'low_stock'
      'inventory'
    when 'out_of_stock'
      'warning'
    when 'order'
      'shopping_bag'
    when 'reservation'
      'calendar'
    else
      'notifications'
    end
  end
  
  # Get appropriate color based on notification type
  def color_class
    case notification_type
    when 'low_stock'
      'text-yellow-500'
    when 'out_of_stock'
      'text-red-500'
    when 'order'
      'text-blue-500'
    when 'reservation'
      'text-green-500'
    else
      'text-gray-500'
    end
  end
  
  # Get link to related resource for admin dashboard
  def admin_path
    case resource_type
    when 'MerchandiseVariant'
      "/admin/merchandise?variant=#{resource_id}"
    when 'MerchandiseItem'
      "/admin/merchandise?item=#{resource_id}"
    when 'Order'
      "/admin/orders?order=#{resource_id}"
    when 'Reservation'
      "/admin/reservations?reservation=#{resource_id}"
    else
      "/admin"
    end
  end
  
  # Format the timestamp for display
  def formatted_timestamp
    created_at.strftime("%b %d, %Y %H:%M")
  end
  
  def as_json(options = {})
    super(options).merge({
      'icon_class' => icon_class,
      'color_class' => color_class,
      'admin_path' => admin_path,
      'formatted_timestamp' => formatted_timestamp
    })
  end
end
