# app/models/location_capacity.rb
class LocationCapacity < ApplicationRecord
  include TenantScoped
  
  # Associations
  belongs_to :restaurant
  belongs_to :location
  
  # Validations
  validates :restaurant_id, presence: true
  validates :location_id, presence: true, uniqueness: { scope: :restaurant_id }
  validates :total_capacity, numericality: { greater_than: 0 }
  validates :default_table_capacity, numericality: { greater_than: 0 }
  
  # Scopes
  scope :for_location, ->(location_id) { where(location_id: location_id) }
  
  # Get total capacity for a specific location
  def self.capacity_for_location(location_id)
    cap = find_by(location_id: location_id)
    cap ? cap.total_capacity : 0
  end
  
  # Get available capacity for a given time
  def available_capacity_at(datetime)
    # Start with total capacity
    capacity = total_capacity
    
    # Subtract capacity used by reservations at this time
    overlapping_reservations = Reservation.where(location_id: location_id)
                                         .where.not(status: %w[canceled finished no_show])
                                         .where('start_time <= ? AND start_time + (duration_minutes * interval \'1 minute\') >= ?', 
                                                datetime, datetime)
    
    # Subtract all party sizes
    reservations_capacity = overlapping_reservations.sum(:party_size)
    capacity -= reservations_capacity
    
    # Ensure we don't return negative capacity
    [capacity, 0].max
  end
  
  # Check if there's enough capacity for a party at a given time
  def can_accommodate?(party_size, datetime)
    available_capacity_at(datetime) >= party_size
  end
end
