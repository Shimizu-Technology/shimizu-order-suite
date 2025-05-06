# app/models/location.rb
class Location < ApplicationRecord
  include TenantScoped
  include Broadcastable
  
  # Define which attributes should trigger broadcasts when changed
  broadcasts_on :name, :address, :phone_number, :is_active, :is_default, :email, :description
  
  # Associations
  belongs_to :restaurant
  belongs_to :current_layout, class_name: 'Layout', optional: true, foreign_key: 'current_layout_id'
  has_many :orders, dependent: :restrict_with_error
  has_one :location_capacity, dependent: :destroy
  has_many :reservations, dependent: :restrict_with_error
  has_many :blocked_periods, dependent: :destroy
  has_many :layouts, dependent: :restrict_with_error
  has_many :seat_sections
  
  # Validations
  validates :name, presence: true
  validates :is_default, uniqueness: { scope: :restaurant_id, if: :is_default? }
  
  # Callbacks
  before_save :ensure_only_one_default_per_restaurant, if: :is_default_changed?
  
  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :default, -> { where(is_default: true) }
  
  # Class methods
  def self.default_for_restaurant(restaurant_id)
    where(restaurant_id: restaurant_id, is_default: true).first
  end
  
  # Instance methods
  def make_default!
    return if is_default?
    
    # Use a transaction to ensure atomicity
    Location.transaction do
      # First, unset any existing default location for this restaurant
      Location.where(restaurant_id: restaurant_id, is_default: true)
             .where.not(id: id)
             .update_all(is_default: false)
      
      # Then set this location as default
      update!(is_default: true)
    end
  end
  
  # Override as_json to provide a consistent JSON representation
  def as_json(options = {})
    data = super(options)
    
    # Add order count if requested
    if options[:include_order_count]
      data[:order_count] = orders.count
    end
    
    data
  end
  
  private
  
  def ensure_only_one_default_per_restaurant
    return unless is_default?
    
    # Unset any existing default location for this restaurant
    Location.where(restaurant_id: restaurant_id, is_default: true)
           .where.not(id: id)
           .update_all(is_default: false)
  end
end
