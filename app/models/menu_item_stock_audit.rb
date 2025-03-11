class MenuItemStockAudit < ApplicationRecord
  apply_default_scope
  
  belongs_to :menu_item
  belongs_to :user, optional: true
  belongs_to :order, optional: true
  
  validates :previous_quantity, :new_quantity, presence: true, numericality: { only_integer: true }
  
  # Predefined reason categories
  REASONS = {
    damaged: 'Damaged', 
    sale: 'Sale',
    restock: 'Restock',
    adjustment: 'Inventory Adjustment',
    other: 'Other'
  }
  
  # Get quantity change (positive for increases, negative for decreases)
  def quantity_change
    new_quantity - previous_quantity
  end
  
  # Helper method to create a damaged item audit
  def self.create_damaged_record(menu_item, quantity, reason_details, user)
    return unless menu_item.enable_stock_tracking
    
    previous = menu_item.damaged_quantity || 0
    new_damaged = previous + quantity.to_i
    
    create!(
      menu_item: menu_item,
      previous_quantity: previous,
      new_quantity: new_damaged,
      reason: "#{REASONS[:damaged]}: #{reason_details}",
      user: user
    )
  end
  
  # Helper method to create a stock quantity update audit
  def self.create_stock_record(menu_item, new_stock, reason_type, reason_details = nil, user = nil, order = nil)
    return unless menu_item.enable_stock_tracking
    
    previous = menu_item.stock_quantity || 0
    
    full_reason = if reason_details.present?
                    "#{REASONS[reason_type.to_sym]}: #{reason_details}"
                  else
                    REASONS[reason_type.to_sym]
                  end
    
    create!(
      menu_item: menu_item,
      previous_quantity: previous,
      new_quantity: new_stock,
      reason: full_reason,
      user: user,
      order: order
    )
  end
end
