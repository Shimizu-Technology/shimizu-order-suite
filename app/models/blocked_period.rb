# app/models/blocked_period.rb
class BlockedPeriod < ApplicationRecord
  include TenantScoped
  
  # Associations
  belongs_to :restaurant
  belongs_to :location, optional: true
  belongs_to :seat_section, optional: true
  
  # Validations
  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :reason, presence: true
  validate :end_time_after_start_time
  validate :must_have_valid_scope
  
  # Scopes
  scope :active, -> { where('end_time > ?', Time.current) }
  scope :for_location, ->(location_id) { where(location_id: location_id) }
  scope :for_seat_section, ->(seat_section_id) { where(seat_section_id: seat_section_id) }
  
  # Check if a given time period overlaps with this blocked period
  def overlaps?(start_datetime, end_datetime)
    (start_time <= end_datetime) && (end_time >= start_datetime)
  end
  
  private
  
  def end_time_after_start_time
    if start_time.present? && end_time.present? && end_time <= start_time
      errors.add(:end_time, "must be after start time")
    end
  end
  
  def must_have_valid_scope
    # Ensure the blocked period has at least one scope (restaurant-wide, location-specific, or seat-section-specific)
    if restaurant_id.blank? && location_id.blank? && seat_section_id.blank?
      errors.add(:base, "Blocked period must be associated with a restaurant, location, or seat section")
    end
    
    # Ensure proper scoping hierarchy (a seat section must be in the specified location)
    if location_id.present? && seat_section_id.present?
      section = SeatSection.find_by(id: seat_section_id)
      if section && section.location_id != location_id
        errors.add(:seat_section_id, "must belong to the specified location")
      end
    end
  end
end
