class MerchandiseVariant < ApplicationRecord
  belongs_to :merchandise_item
  
  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :price_adjustment, numericality: { greater_than_or_equal_to: 0 }
  validates :low_stock_threshold, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true
  
  # Scopes for filtering
  scope :in_stock, -> { where('stock_quantity > 0') }
  scope :out_of_stock, -> { where(stock_quantity: 0) }
  scope :low_stock, -> { where('stock_quantity > 0 AND stock_quantity <= COALESCE(low_stock_threshold, 5)') }
  
  # Stock status methods
  def in_stock?
    stock_quantity > 0
  end
  
  def actual_low_stock_threshold
    low_stock_threshold || merchandise_item.actual_low_stock_threshold || 5
  end
  
  def low_stock?
    in_stock? && stock_quantity <= actual_low_stock_threshold
  end
  
  def stock_status
    return :out_of_stock unless in_stock?
    return :low_stock if low_stock?
    :in_stock
  end
  
  # Simplified method to reduce stock
  def reduce_stock!(quantity = 1, allow_negative = false, order = nil, user = nil)
    previous_quantity = stock_quantity
    new_quantity = allow_negative ? (stock_quantity - quantity) : [stock_quantity - quantity, 0].max
    
    transaction do
      update!(stock_quantity: new_quantity)
      
      # Update parent item stock status
      merchandise_item.update_stock_status!
    end
    
    new_quantity
  end
  
  # Simplified method to increase stock
  def add_stock!(quantity = 1, reason = "Manual restock", user = nil)
    previous_quantity = stock_quantity
    new_quantity = stock_quantity + quantity
    
    transaction do
      update!(stock_quantity: new_quantity)
      
      # Update parent item stock status
      merchandise_item.update_stock_status!
    end
    
    new_quantity
  end
  
  def as_json(options = {})
    result = super(options).merge(
      'price_adjustment' => price_adjustment.to_f,
      'final_price' => (merchandise_item.base_price + price_adjustment).to_f,
      'in_stock' => in_stock?,
      'low_stock' => low_stock?,
      'stock_status' => stock_status,
      'low_stock_threshold' => actual_low_stock_threshold
    )
    
    result
  end
  
  def available?
    stock_quantity > 0
  end
end
