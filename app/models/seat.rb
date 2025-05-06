# app/models/seat.rb
class Seat < ApplicationRecord
  apply_default_scope

  # Even if you see status in an attribute hash, don't treat it as a DB column
  self.ignored_columns = [ :status ]

  belongs_to :seat_section
  # Define path to restaurant through associations for tenant isolation
  has_one :layout, through: :seat_section
  has_one :restaurant, through: :layout
  has_one :location, through: :seat_section

  has_many :seat_allocations, dependent: :destroy
  has_many :reservations, through: :seat_allocations
  has_many :waitlist_entries, through: :seat_allocations

  validates :capacity, numericality: { greater_than: 0 }
  validates :min_capacity, numericality: { greater_than: 0 }
  validate :max_capacity_is_valid

  # Override with_restaurant_scope for indirect restaurant association
  def self.with_restaurant_scope
    if current_restaurant
      joins(seat_section: :layout).where(layouts: { restaurant_id: current_restaurant.id })
    else
      all
    end
  end

  # Staff can rename the seat by updating the :label field
  # Example: seat.update(label: "A1")
  
  # Find seats with a specific category
  # @param category [String] The category to filter by
  # @return [ActiveRecord::Relation] Seats with the specified category
  def self.with_category(category)
    where(category: category)
  end
  
  # Find seats in a specific location
  # @param location_id [Integer] The location ID to filter by
  # @return [ActiveRecord::Relation] Seats in the specified location
  def self.in_location(location_id)
    joins(:seat_section).where(seat_sections: { location_id: location_id })
  end

  # Check if this seat can accommodate a party of the given size
  # @param party_size [Integer] Number of people in the party
  # @return [Boolean] true if the seat can accommodate the party, false otherwise
  def is_available_for_party_size?(party_size)
    return false if party_size.nil? || !party_size.is_a?(Integer) || party_size <= 0
    
    # A party must be at least as large as min_capacity
    return false if party_size < min_capacity
    
    # If max_capacity is set, the party must not exceed it
    return false if max_capacity.present? && party_size > max_capacity
    
    # Otherwise, the seat can accommodate the party
    true
  end

  # Debug callbacks (kept as is)
  before_validation :debug_before_validation
  after_validation :debug_after_validation
  after_create :debug_after_create
  after_update :debug_after_update

  private
  
  # Validate that max_capacity is greater than or equal to min_capacity when present
  def max_capacity_is_valid
    if max_capacity.present? && max_capacity < min_capacity
      errors.add(:max_capacity, "must be greater than or equal to min_capacity")
    end
  end

  def debug_before_validation
    Rails.logger.debug "Seat#before_validation => #{attributes.inspect}"
  end

  def debug_after_validation
    if errors.any?
      Rails.logger.debug "Seat#after_validation => ERRORS: #{errors.full_messages}"
    else
      Rails.logger.debug "Seat#after_validation => no validation errors."
    end
  end

  def debug_after_create
    Rails.logger.debug "Seat#after_create => Seat record created: #{attributes.inspect}"
  end

  def debug_after_update
    Rails.logger.debug "Seat#after_update => Seat record updated: #{attributes.inspect}"
  end
end
