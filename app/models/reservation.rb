class Reservation < ApplicationRecord
  # Default scope to current restaurant
  default_scope { with_restaurant_scope }
  # Force ActiveRecord to treat them as real columns:
  attribute :seat_preferences, :json, default: []
  attribute :duration_minutes, :integer, default: 60
  
  belongs_to :restaurant
  has_many :seat_allocations, dependent: :nullify
  has_many :seats, through: :seat_allocations

  validates :restaurant_id, presence: true
  validates :start_time, presence: true
  validates :party_size,
            presence: true,
            numericality: { greater_than: 0 }
  validates :contact_name, presence: true

  # The check constraint in the DB enforces only these statuses:
  #   booked, reserved, seated, finished, canceled, no_show
  # This before_validation sets status to 'booked' if none is provided.
  before_validation :default_status, on: :create

  # Ensure seat_preferences is always an array
  before_save :normalize_seat_preferences

  # Auto-calculate end_time from duration_minutes
  before_save :update_end_time_from_duration

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
    self.status = 'booked' if status.blank?
  end

  def normalize_seat_preferences
    Rails.logger.debug "DEBUG: in normalize_seat_preferences, before: seat_preferences=#{seat_preferences.inspect}"
    # Only reset if it's NOT an Array at all
    self.seat_preferences = [] unless seat_preferences.is_a?(Array)
    Rails.logger.debug "DEBUG: in normalize_seat_preferences, after: seat_preferences=#{seat_preferences.inspect}"
  end

  def update_end_time_from_duration
    return if start_time.blank?

    self.duration_minutes ||= 60  # default to 60 if not provided
    self.end_time = start_time + duration_minutes.minutes
  end
end
