# app/models/operating_hour.rb

class OperatingHour < ApplicationRecord
  # Default scope to current restaurant
  default_scope { with_restaurant_scope }
  belongs_to :restaurant

  validates :day_of_week, inclusion: { in: 0..6 }
  validates :open_time, presence: true, unless: :closed?
  validates :close_time, presence: true, unless: :closed?

  validate :close_after_open

  def close_after_open
    return if closed? || open_time.nil? || close_time.nil?
    if close_time <= open_time
      errors.add(:close_time, "must be later than open_time")
    end
  end
end
