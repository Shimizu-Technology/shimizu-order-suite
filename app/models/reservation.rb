class Reservation < ApplicationRecord
  include TenantScoped
  
  # Force ActiveRecord to treat them as real columns:
  attribute :seat_preferences, :json, default: []
  attribute :duration_minutes, :integer, default: 60
  has_many :seat_allocations, dependent: :nullify
  has_many :seats, through: :seat_allocations
  belongs_to :location, optional: true

  validates :restaurant_id, presence: true
  validates :start_time, presence: true
  validates :party_size,
            presence: true,
            numericality: { greater_than: 0 }
  validates :contact_name, presence: true
  validates :reservation_number, uniqueness: true, allow_nil: true
  
  # Generate and assign a reservation number before creation
  before_create :assign_reservation_number

  # The check constraint in the DB enforces only these statuses:
  #   booked, reserved, seated, finished, canceled, no_show
  # This before_validation sets status to 'booked' if none is provided.
  before_validation :default_status, on: :create

  # Ensure seat_preferences is always an array
  before_save :normalize_seat_preferences

  # Auto-calculate end_time from duration_minutes
  before_save :update_end_time_from_duration
  
  # Set default location if none provided
  before_validation :set_default_location, on: :create

  ############################
  ## Return the labels of currently allocated seats
  def seat_labels
    seat_allocations
      .where(released_at: nil)
      .includes(:seat) # prevents N+1 queries
      .map { |alloc| alloc.seat.label }
  end
  ############################

  private

  def default_status
    self.status = "booked" if status.blank?
  end

  def normalize_seat_preferences
    Rails.logger.debug "DEBUG: in normalize_seat_preferences, before: seat_preferences=#{seat_preferences.inspect}"
    # Only reset if it's NOT an Array at all
    self.seat_preferences = [] unless seat_preferences.is_a?(Array)
    Rails.logger.debug "DEBUG: in normalize_seat_preferences, after: seat_preferences=#{seat_preferences.inspect}"
  end

  def assign_reservation_number
    return if reservation_number.present? # Skip if already assigned
    
    # Make sure we have a restaurant_id
    unless restaurant_id.present?
      Rails.logger.error("Cannot assign reservation number: restaurant_id is missing for reservation")
      return
    end
    
    # Generate a new reservation number using the ReservationCounter
    self.reservation_number = ReservationCounter.next_reservation_number(restaurant_id)
    
    # Log for debugging
    Rails.logger.info("Assigned reservation number #{reservation_number} to reservation for restaurant #{restaurant_id}")
  rescue => e
    # Log error but don't prevent reservation creation
    Rails.logger.error("Error assigning reservation number: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
  end
  
  def update_end_time_from_duration
    return if start_time.blank?

    self.duration_minutes ||= 60  # default to 60 if not provided
    self.end_time = start_time + duration_minutes.minutes
  end
  
  def set_default_location
    # Only set default location if restaurant exists and no location is specified
    return unless restaurant_id.present? && location_id.blank?
    
    begin
      # Find the restaurant
      restaurant = Restaurant.find_by(id: restaurant_id)
      return unless restaurant
      
      # Try to find the default location for this restaurant
      default_location = restaurant.default_location
      
      if default_location
        self.location_id = default_location.id
        Rails.logger.info "Setting default location (#{default_location.name}) for reservation"
      else
        # If there's no default location but at least one location exists, use the first active one
        active_location = restaurant.active_locations.first
        if active_location
          self.location_id = active_location.id
          Rails.logger.info "No default location found, using first active location (#{active_location.name})"
        else
          # No locations at all, but that's ok - location is optional
          Rails.logger.info "No locations found for restaurant (#{restaurant_id}), continuing without a location"
          self.location_id = nil # Explicitly set to nil to avoid potential issues
        end
      end
    rescue => e
      # Log the error but continue - location is optional
      Rails.logger.error "Error setting default location for reservation: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      self.location_id = nil # Reset to ensure a clean state
    end
  end
end
