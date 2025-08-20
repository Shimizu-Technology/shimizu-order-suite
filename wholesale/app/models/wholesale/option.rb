module Wholesale
  class Option < ApplicationRecord
    self.table_name = 'wholesale_options'
    
    belongs_to :option_group, class_name: 'Wholesale::OptionGroup', foreign_key: 'wholesale_option_group_id'
    
    validates :name, presence: true
    validates :name, uniqueness: { scope: :wholesale_option_group_id, message: "must be unique within the option group" }
    validates :additional_price, numericality: { greater_than_or_equal_to: 0 }
    validates :position, numericality: { greater_than_or_equal_to: 0 }
    validates :total_ordered, numericality: { greater_than_or_equal_to: 0 }
    validates :total_revenue, numericality: { greater_than_or_equal_to: 0 }
    
    # Future inventory validations (when inventory tracking is enabled)
    validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :damaged_quantity, numericality: { greater_than_or_equal_to: 0 }
    validates :low_stock_threshold, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validate :damaged_quantity_not_greater_than_stock, if: :inventory_tracking_enabled?
    
    scope :available, -> { where(available: true) }
    scope :unavailable, -> { where(available: false) }
    scope :by_position, -> { order(:position) }
    
    # Set default position before creation
    before_create :set_default_position
    
    # Sales tracking methods
    def add_sale!(quantity, revenue)
      increment!(:total_ordered, quantity)
      increment!(:total_revenue, revenue)
    end
    
    # Check if this option has inventory tracking enabled through its option group
    def inventory_tracking_enabled?
      option_group&.inventory_tracking_enabled? || false
    end
    
    # Get available stock for this option (future feature)
    def available_stock
      return nil unless inventory_tracking_enabled?
      return nil if stock_quantity.nil?
      [stock_quantity - (damaged_quantity || 0), 0].max
    end
    
    # Check if option is in stock (future feature)
    def in_stock?
      return available unless inventory_tracking_enabled?
      available && (stock_quantity.nil? || available_stock > 0)
    end
    
    # Check if option is out of stock (future feature)
    def out_of_stock?
      return !available unless inventory_tracking_enabled?
      !available || (stock_quantity.present? && available_stock <= 0)
    end
    
    # Check if option is low stock (future feature)
    def low_stock?(threshold = nil)
      return false unless inventory_tracking_enabled?
      return false if stock_quantity.nil? || available_stock.nil?
      
      threshold ||= low_stock_threshold || 5
      available_stock <= threshold && available_stock > 0
    end
    
    # Get the final price including any additional price
    def final_price
      base_price_cents = option_group&.wholesale_item&.price_cents || 0
      base_price = base_price_cents / 100.0
      (base_price + (additional_price || 0)).to_f
    end
    
    # Display methods
    def display_name
      name
    end
    
    def full_display_name
      item_name = option_group&.wholesale_item&.name || "Unknown Item"
      "#{item_name} - #{name}"
    end
    
    private
    
    def set_default_position
      return if position.present? && position > 0
      
      max_position = option_group&.options&.maximum(:position) || 0
      self.position = max_position + 1
    end
    
    def damaged_quantity_not_greater_than_stock
      return unless stock_quantity.present? && damaged_quantity.present?
      
      if damaged_quantity > stock_quantity
        errors.add(:damaged_quantity, "cannot be greater than stock quantity")
      end
    end
  end
end