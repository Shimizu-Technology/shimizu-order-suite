class Wholesale::OptionStockAudit < ApplicationRecord
  belongs_to :wholesale_option, class_name: 'Wholesale::Option'
  belongs_to :user, optional: true
  belongs_to :order, class_name: 'Wholesale::Order', optional: true
  
  validates :audit_type, presence: true
  validates :audit_type, inclusion: { in: %w[stock_update damaged order_placed order_cancelled restock manual_adjustment] }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_option, ->(option) { where(wholesale_option: option) }
  scope :by_type, ->(type) { where(audit_type: type) }
  
  # Class methods for creating audit records
  def self.create_stock_record(option, new_quantity, reason_type, reason_details = nil, user = nil, order = nil)
    previous_quantity = option.stock_quantity || 0
    quantity_change = new_quantity - previous_quantity
    
    create!(
      wholesale_option: option,
      audit_type: 'stock_update',
      quantity_change: quantity_change,
      previous_quantity: previous_quantity,
      new_quantity: new_quantity,
      reason: build_reason(reason_type, reason_details, order),
      user: user,
      order: order
    )
  end
  
  def self.create_damaged_record(option, damaged_quantity, reason, user = nil)
    create!(
      wholesale_option: option,
      audit_type: 'damaged',
      quantity_change: -damaged_quantity,
      previous_quantity: option.damaged_quantity || 0,
      new_quantity: (option.damaged_quantity || 0) + damaged_quantity,
      reason: reason,
      user: user
    )
  end
  
  def self.create_order_record(option, quantity_change, order, reason_type = 'order_placed')
    previous_stock = option.stock_quantity || 0
    new_stock = previous_stock + quantity_change
    
    create!(
      wholesale_option: option,
      audit_type: reason_type,
      quantity_change: quantity_change,
      previous_quantity: previous_stock,
      new_quantity: new_stock,
      reason: "Order #{order.order_number}: #{reason_type.humanize} - #{option.name}",
      order: order
    )
  end
  
  private
  
  def self.build_reason(reason_type, reason_details, order = nil)
    case reason_type
    when 'restock'
      "Option inventory restocked#{reason_details ? ": #{reason_details}" : ''}"
    when 'manual_adjustment'
      "Manual option adjustment#{reason_details ? ": #{reason_details}" : ''}"
    when 'system_correction'
      "System option correction#{reason_details ? ": #{reason_details}" : ''}"
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
