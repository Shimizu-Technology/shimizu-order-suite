# app/models/option.rb
class Option < ApplicationRecord
  apply_default_scope

  belongs_to :option_group
  # Define path to restaurant through associations for tenant isolation
  has_one :menu_item, through: :option_group
  has_one :menu, through: :menu_item
  has_one :restaurant, through: :menu
  
  # Stock audit association
  has_many :stock_audits, class_name: 'OptionStockAudit'

  validates :name, presence: true
  validates :additional_price, numericality: { greater_than_or_equal_to: 0.0 }
  validates :is_preselected, inclusion: { in: [true, false] }

  # Inventory tracking
  enum stock_status: {
    in_stock: 0,
    out_of_stock: 1,
    low_stock: 2
  }
  
  # Calculate available quantity (stock minus damaged)
  def available_quantity
    return nil unless enable_stock_tracking
    total = stock_quantity.to_i
    damaged = damaged_quantity.to_i
    total - damaged
  end
  
  # Update stock status based on available quantity
  def update_stock_status!
    return unless enable_stock_tracking
    
    available = available_quantity
    threshold = low_stock_threshold || 10
    
    new_status = if available <= 0
                   :out_of_stock
                 elsif available <= threshold
                   :low_stock
                 else
                   :in_stock
                 end
    
    update_column(:stock_status, new_status) unless stock_status == new_status.to_s
  end
  
  # Mark items as damaged
  def mark_as_damaged(quantity, reason, user = nil)
    return false unless enable_stock_tracking
    
    transaction do
      # Record the current quantities
      previous_damaged = damaged_quantity.to_i
      
      # Update the damaged quantity
      new_damaged = previous_damaged + quantity
      update!(damaged_quantity: new_damaged)
      
      # Create an audit record
      OptionStockAudit.create_stock_record(
        self,
        stock_quantity,
        :damaged,
        reason,
        user
      )
      
      # Update the stock status
      update_stock_status!
      
      true
    end
  rescue => e
    Rails.logger.error("Error marking option as damaged: #{e.message}")
    false
  end
  
  # Method to handle stock reduction during order placement
  def reduce_stock!(quantity = 1)
    return true unless enable_stock_tracking
    
    transaction do
      new_quantity = [stock_quantity - quantity, 0].max
      update!(stock_quantity: new_quantity)
      update_stock_status!
    end
  end

  # Override with_restaurant_scope for indirect restaurant association
  def self.with_restaurant_scope
    if current_restaurant
      joins(option_group: { menu_item: :menu }).where(menus: { restaurant_id: current_restaurant.id })
    else
      all
    end
  end

  # Instead of overriding as_json, we provide a method that returns a float.
  # The controller uses `methods: [:additional_price_float]` to include it.
  def additional_price_float
    additional_price.to_f
  end

  # Calculate available quantity (stock minus damaged)
  def available_quantity
    return nil unless enable_stock_tracking
    [stock_quantity.to_i - damaged_quantity.to_i, 0].max
  end

  # Check if option is available based on inventory
  def available_for_order?
    return true unless enable_stock_tracking
    available_quantity.to_i > 0
  end

  # Update the stock status based on quantity
  def update_stock_status!
    return unless enable_stock_tracking
    
    available = available_quantity
    threshold = low_stock_threshold || 10
    
    new_status = if available <= 0
                   :out_of_stock
                 elsif available <= threshold
                   :low_stock
                 else
                   :in_stock
                 end
    
    update_column(:stock_status, new_status) unless stock_status == new_status.to_s
  end

  # Reduce stock when an order is placed
  def reduce_stock!(quantity = 1, order = nil)
    return true unless enable_stock_tracking
    
    new_quantity = [stock_quantity.to_i - quantity, 0].max
    
    transaction do
      # Create audit record
      OptionStockAudit.create_stock_record(self, new_quantity, :order, "Order placed", nil, order)
      
      # Update stock quantity
      update!(stock_quantity: new_quantity)
      update_stock_status!
    end
  end

  # Increase stock when an order is refunded/canceled
  def increase_stock!(quantity = 1, order = nil)
    return true unless enable_stock_tracking
    
    new_quantity = stock_quantity.to_i + quantity
    
    transaction do
      # Create audit record
      OptionStockAudit.create_stock_record(self, new_quantity, :return, "Order returned/canceled", nil, order)
      
      # Update stock quantity
      update!(stock_quantity: new_quantity)
      update_stock_status!
    end
  end
  
  # Mark items as damaged
  def mark_as_damaged(quantity = 1, reason = nil, user = nil)
    return true unless enable_stock_tracking
    
    transaction do
      # Increase damaged quantity
      new_damaged = damaged_quantity.to_i + quantity
      update!(damaged_quantity: new_damaged)
      
      # Create audit record with the reason
      OptionStockAudit.create_stock_record(self, stock_quantity, :damaged, reason, user)
      
      # Update stock status
      update_stock_status!
    end
  end

  # Override as_json to include inventory fields
  def as_json(options = {})
    result = super(options)
    
    if enable_stock_tracking
      result.merge!(
        "enable_stock_tracking" => enable_stock_tracking,
        "stock_quantity" => stock_quantity.to_i,
        "stock_status" => stock_status
      )
    end
    
    result
  end
end
