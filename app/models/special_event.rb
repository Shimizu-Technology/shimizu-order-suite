# app/models/special_event.rb
class SpecialEvent < ApplicationRecord
  # Default scope to current restaurant
  default_scope { with_restaurant_scope }
  belongs_to :restaurant

  validates :event_date, presence: true

  # Example partial-day check
  validate :end_time_after_start_time, if: -> { start_time.present? && end_time.present? }

  before_save :clamp_max_capacity

  private

  def end_time_after_start_time
    if end_time <= start_time
      errors.add(:end_time, "must be after start_time")
    end
  end

  # This ensures the max_capacity never exceeds the total seat count
  # or gets set to zero. If the user sets it to 9999 or 0, we clamp
  # it to restaurant.current_seats.count
  def clamp_max_capacity
    total_seats = restaurant.current_seats.count
    # If max_capacity is nil, zero, or bigger than total seats, clamp it
    if max_capacity.nil? || max_capacity < 1 || max_capacity > total_seats
      self.max_capacity = total_seats
    end
  end
end
