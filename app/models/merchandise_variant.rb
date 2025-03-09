class MerchandiseVariant < ApplicationRecord
  belongs_to :merchandise_item
  
  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :price_adjustment, numericality: { greater_than_or_equal_to: 0 }
  
  def as_json(options = {})
    super(options).merge(
      'price_adjustment' => price_adjustment.to_f,
      'final_price' => (merchandise_item.base_price + price_adjustment).to_f
    )
  end
  
  def available?
    stock_quantity > 0
  end
end
