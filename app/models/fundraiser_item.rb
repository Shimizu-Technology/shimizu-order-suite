# app/models/fundraiser_item.rb

class FundraiserItem < ApplicationRecord
  # Associations
  belongs_to :fundraiser
  has_many :option_groups, as: :optionable, dependent: :destroy
  
  # Include IndirectTenantScoped for tenant isolation through fundraiser
  include IndirectTenantScoped
  
  # Define the path to restaurant for tenant isolation
  tenant_path through: :fundraiser, foreign_key: 'restaurant_id'
  
  # Validations
  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  
  # Stock tracking validations
  validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :low_stock_threshold, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true
  
  # Scopes
  scope :active, -> { where(active: true) }
  
  # Callbacks
  before_save :reset_inventory_fields_if_tracking_disabled
  
  # Inventory tracking methods
  def available_quantity
    return nil unless enable_stock_tracking
    stock_quantity || 0
  end
  
  def low_stock?
    return false unless enable_stock_tracking
    return false if low_stock_threshold.nil? || stock_quantity.nil?
    stock_quantity <= low_stock_threshold
  end
  
  def out_of_stock?
    return false unless enable_stock_tracking
    stock_quantity.to_i <= 0
  end
  
  def update_stock(quantity_change)
    return unless enable_stock_tracking
    
    # Don't allow stock to go below zero
    new_quantity = [0, (stock_quantity || 0) + quantity_change].max
    update(stock_quantity: new_quantity)
  end
  
  private
  
  def reset_inventory_fields_if_tracking_disabled
    unless enable_stock_tracking
      self.stock_quantity = nil
      self.low_stock_threshold = nil
    end
  end
end
