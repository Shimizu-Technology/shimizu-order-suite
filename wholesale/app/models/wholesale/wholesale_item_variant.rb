module Wholesale
  # DEPRECATED: This model is deprecated in favor of the new Option Groups system.
  # Use Wholesale::OptionGroup and Wholesale::Option instead.
  # This model is kept for backward compatibility only.
  class WholesaleItemVariant < ApplicationRecord
    self.table_name = 'wholesale_item_variants'
    
    belongs_to :wholesale_item, class_name: 'Wholesale::Item'
    
    validates :sku, presence: true, uniqueness: true
    validates :size, presence: true, if: -> { color.blank? }
    validates :color, presence: true, if: -> { size.blank? }
    validates :price_adjustment, numericality: { greater_than_or_equal_to: 0 }
    validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }
    validates :low_stock_threshold, numericality: { greater_than_or_equal_to: 0 }
    validates :total_ordered, numericality: { greater_than_or_equal_to: 0 }
    validates :total_revenue, numericality: { greater_than_or_equal_to: 0 }
    
    # Scopes
    scope :active, -> { where(active: true) }
    scope :inactive, -> { where(active: false) }
    scope :by_size, ->(size) { where(size: size) }
    scope :by_color, ->(color) { where(color: color) }
    
    # Price calculation
    def final_price
      (wholesale_item.price + (price_adjustment || 0)).to_f
    end
    
    # Display methods
    def display_name
      parts = []
      parts << size if size.present?
      parts << color if color.present?
      parts.join(' - ')
    end
    
    def full_display_name
      "#{wholesale_item.name} - #{display_name}"
    end
    
    # Sales tracking methods
    def add_sale!(quantity, revenue)
      increment!(:total_ordered, quantity)
      increment!(:total_revenue, revenue)
    end
    
    # Stock methods (for future inventory management)
    def in_stock?(quantity = 1)
      return true unless wholesale_item.track_inventory?
      stock_quantity >= quantity
    end
    
    def can_purchase?(quantity = 1)
      return true unless wholesale_item.track_inventory?
      return true if wholesale_item.allow_sale_with_no_stock?
      in_stock?(quantity)
    end
    
    def reduce_stock!(quantity)
      return true unless wholesale_item.track_inventory?
      return false unless in_stock?(quantity)
      
      decrement!(:stock_quantity, quantity)
      true
    end
    
    def add_stock!(quantity)
      return false unless wholesale_item.track_inventory?
      increment!(:stock_quantity, quantity)
      true
    end
  end
end
