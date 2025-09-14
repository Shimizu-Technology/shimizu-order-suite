# app/models/wholesale/variant_stock_audit.rb

class Wholesale::VariantStockAudit < ApplicationRecord
  belongs_to :wholesale_item_variant, class_name: 'Wholesale::ItemVariant'
  belongs_to :user, optional: true
  belongs_to :order, class_name: 'Wholesale::Order', optional: true
  
  validates :audit_type, presence: true
  validates :audit_type, inclusion: { in: %w[stock_update damaged order_placed order_cancelled restock manual_adjustment status_change variant_created variant_deleted] }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_variant, ->(variant) { where(wholesale_item_variant: variant) }
  scope :by_type, ->(type) { where(audit_type: type) }
  scope :by_user, ->(user) { where(user: user) }
  scope :for_order, ->(order) { where(order: order) }
  
  # Delegate variant information for easy access
  delegate :variant_key, :variant_name, :item, to: :wholesale_item_variant
  
  # Class methods for creating audit records
  def self.create_stock_record(variant, new_quantity, reason_type, reason_details = nil, user = nil, order = nil, previous_quantity = nil)
    # Use provided previous_quantity or get current value (for cases where variant hasn't been updated yet)
    previous_quantity = previous_quantity || variant.stock_quantity || 0
    quantity_change = new_quantity - previous_quantity
    
    create!(
      wholesale_item_variant: variant,
      audit_type: 'stock_update',
      quantity_change: quantity_change,
      previous_quantity: previous_quantity,
      new_quantity: new_quantity,
      reason: build_reason(reason_type, reason_details, order, variant),
      user: user,
      order: order,
      metadata: {
        variant_key: variant.variant_key,
        variant_name: variant.variant_name,
        item_id: variant.wholesale_item.id,
        item_name: variant.wholesale_item.name
      }
    )
  end
  
  def self.create_damaged_record(variant, damaged_quantity, reason, user = nil)
    create!(
      wholesale_item_variant: variant,
      audit_type: 'damaged',
      quantity_change: -damaged_quantity,
      previous_quantity: variant.damaged_quantity || 0,
      new_quantity: (variant.damaged_quantity || 0) + damaged_quantity,
      reason: reason,
      user: user,
      metadata: {
        variant_key: variant.variant_key,
        variant_name: variant.variant_name,
        item_id: variant.wholesale_item.id,
        item_name: variant.wholesale_item.name,
        damaged_quantity: damaged_quantity
      }
    )
  end
  
  def self.create_order_record(variant, quantity_change, order, reason_type = 'order_placed')
    previous_stock = variant.stock_quantity || 0
    new_stock = previous_stock + quantity_change
    
    create!(
      wholesale_item_variant: variant,
      audit_type: reason_type,
      quantity_change: quantity_change,
      previous_quantity: previous_stock,
      new_quantity: new_stock,
      reason: "Order #{order.order_number}: #{reason_type.humanize} - #{variant.variant_name}",
      order: order,
      metadata: {
        variant_key: variant.variant_key,
        variant_name: variant.variant_name,
        item_id: variant.wholesale_item.id,
        item_name: variant.wholesale_item.name,
        order_number: order.order_number,
        customer_name: order.customer_name
      }
    )
  end
  
  def self.create_status_change_record(variant, old_status, new_status, user = nil)
    create!(
      wholesale_item_variant: variant,
      audit_type: 'status_change',
      quantity_change: 0,
      previous_quantity: variant.stock_quantity || 0,
      new_quantity: variant.stock_quantity || 0,
      reason: "Variant status changed from #{old_status ? 'active' : 'inactive'} to #{new_status ? 'active' : 'inactive'}",
      user: user,
      metadata: {
        variant_key: variant.variant_key,
        variant_name: variant.variant_name,
        item_id: variant.wholesale_item.id,
        item_name: variant.wholesale_item.name,
        old_status: old_status,
        new_status: new_status
      }
    )
  end
  
  def self.create_variant_creation_record(variant, user = nil)
    create!(
      wholesale_item_variant: variant,
      audit_type: 'variant_created',
      quantity_change: variant.stock_quantity || 0,
      previous_quantity: 0,
      new_quantity: variant.stock_quantity || 0,
      reason: "Variant created: #{variant.variant_name}",
      user: user,
      metadata: {
        variant_key: variant.variant_key,
        variant_name: variant.variant_name,
        item_id: variant.wholesale_item.id,
        item_name: variant.wholesale_item.name,
        initial_stock: variant.stock_quantity || 0,
        low_stock_threshold: variant.low_stock_threshold
      }
    )
  end
  
  def self.create_variant_deletion_record(variant, user = nil)
    create!(
      wholesale_item_variant: variant,
      audit_type: 'variant_deleted',
      quantity_change: -(variant.stock_quantity || 0),
      previous_quantity: variant.stock_quantity || 0,
      new_quantity: 0,
      reason: "Variant deleted: #{variant.variant_name}",
      user: user,
      metadata: {
        variant_key: variant.variant_key,
        variant_name: variant.variant_name,
        item_id: variant.wholesale_item.id,
        item_name: variant.wholesale_item.name,
        final_stock: variant.stock_quantity || 0,
        final_damaged: variant.damaged_quantity || 0
      }
    )
  end
  
  # Instance methods
  def stock_increase?
    quantity_change > 0
  end
  
  def stock_decrease?
    quantity_change < 0
  end
  
  def stock_neutral?
    quantity_change == 0
  end
  
  def order_related?
    %w[order_placed order_cancelled].include?(audit_type)
  end
  
  def admin_action?
    %w[stock_update damaged restock manual_adjustment status_change].include?(audit_type)
  end
  
  def system_action?
    %w[variant_created variant_deleted].include?(audit_type)
  end
  
  def formatted_change
    return "No change" if quantity_change == 0
    return "+#{quantity_change}" if quantity_change > 0
    quantity_change.to_s
  end
  
  def formatted_reason
    reason.presence || audit_type.humanize
  end
  
  def user_name
    user&.name || user&.email || 'System'
  end
  
  private
  
  def self.build_reason(reason_type, reason_details, order = nil, variant = nil)
    variant_info = variant ? " (#{variant.variant_name})" : ""
    
    case reason_type
    when 'restock'
      "Variant inventory restocked#{variant_info}#{reason_details ? ": #{reason_details}" : ''}"
    when 'manual_adjustment'
      "Manual variant adjustment#{reason_details ? ": #{reason_details}" : ''}#{variant_info}"
    when 'system_correction'
      "System variant correction#{variant_info}#{reason_details ? ": #{reason_details}" : ''}"
    when 'order_placed'
      if order
        "Order placed: #{order.order_number} by #{order.customer_name}#{variant_info}"
      else
        "Order placed#{variant_info}#{reason_details ? ": #{reason_details}" : ''}"
      end
    when 'order_cancelled'
      if order
        "Order cancelled: #{order.order_number} by #{order.customer_name}#{variant_info}"
      else
        "Order cancelled#{variant_info}#{reason_details ? ": #{reason_details}" : ''}"
      end
    else
      "#{reason_details || reason_type.humanize}#{variant_info}"
    end
  end
end
