class Wholesale::ItemStockAudit < ApplicationRecord
  belongs_to :wholesale_item, class_name: 'Wholesale::Item'
  belongs_to :user, optional: true
  belongs_to :order, class_name: 'Wholesale::Order', optional: true
  
  validates :audit_type, presence: true
  validates :audit_type, inclusion: { in: %w[stock_update damaged order_placed order_cancelled restock manual_adjustment] }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_item, ->(item) { where(wholesale_item: item) }
  scope :by_type, ->(type) { where(audit_type: type) }
  
  # Class methods for creating audit records
  def self.create_stock_record(item, new_quantity, reason_type, reason_details = nil, user = nil, order = nil)
    previous_quantity = item.stock_quantity || 0
    quantity_change = new_quantity - previous_quantity
    
    create!(
      wholesale_item: item,
      audit_type: 'stock_update',
      quantity_change: quantity_change,
      previous_quantity: previous_quantity,
      new_quantity: new_quantity,
      reason: build_reason(reason_type, reason_details, order),
      user: user,
      order: order
    )
  end
  
  def self.create_damaged_record(item, damaged_quantity, reason, user = nil)
    create!(
      wholesale_item: item,
      audit_type: 'damaged',
      quantity_change: -damaged_quantity,
      previous_quantity: item.damaged_quantity || 0,
      new_quantity: (item.damaged_quantity || 0) + damaged_quantity,
      reason: reason,
      user: user
    )
  end
  
  def self.create_order_record(item, quantity_change, order, reason_type = 'order_placed')
    previous_stock = item.stock_quantity || 0
    new_stock = previous_stock + quantity_change
    
    create!(
      wholesale_item: item,
      audit_type: reason_type,
      quantity_change: quantity_change,
      previous_quantity: previous_stock,
      new_quantity: new_stock,
      reason: "Order #{order.order_number}: #{reason_type.humanize}",
      order: order
    )
  end
  
  private
  
  def self.build_reason(reason_type, reason_details, order = nil)
    case reason_type
    when 'restock'
      "Inventory restocked#{reason_details ? ": #{reason_details}" : ''}"
    when 'manual_adjustment'
      "Manual adjustment#{reason_details ? ": #{reason_details}" : ''}"
    when 'system_correction'
      "System correction#{reason_details ? ": #{reason_details}" : ''}"
    when 'order_placed'
      if order
        "Order placed: #{order.order_number} by #{order.customer_name}"
      else
        "Order placed#{reason_details ? ": #{reason_details}" : ''}"
      end
    when 'order_cancelled'
      if order
        "Order cancelled: #{order.order_number} by #{order.customer_name}"
      else
        "Order cancelled#{reason_details ? ": #{reason_details}" : ''}"
      end
    else
      reason_details || reason_type.humanize
    end
  end
end
