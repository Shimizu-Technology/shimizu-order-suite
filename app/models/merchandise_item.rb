class MerchandiseItem < ApplicationRecord
  apply_default_scope
  
  belongs_to :merchandise_collection
  has_many :merchandise_variants, dependent: :destroy
  
  # Define path to restaurant through associations for tenant isolation
  has_one :restaurant, through: :merchandise_collection
  
  validates :name, presence: true
  validates :base_price, numericality: { greater_than_or_equal_to: 0 }
  
  # Stock status enum
  enum :stock_status, {
    in_stock: 0,
    out_of_stock: 1,
    low_stock: 2
  }, prefix: true
  
  # Override with_restaurant_scope for indirect restaurant association
  def self.with_restaurant_scope
    if current_restaurant
      joins(:merchandise_collection).where(merchandise_collections: { restaurant_id: current_restaurant.id })
    else
      all
    end
  end
  
  def as_json(options = {})
    result = super(options).merge(
      'base_price' => base_price.to_f,
      'image_url' => image_url,
      'stock_status' => stock_status,
      'status_note' => status_note
    )
    
    # Add variants if requested
    if options[:include_variants]
      result['variants'] = merchandise_variants.map(&:as_json)
    end
    
    result
  end
end
