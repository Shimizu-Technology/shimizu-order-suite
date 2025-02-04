# app/models/seat.rb
class Seat < ApplicationRecord
  # Even if you see status in an attribute hash, don’t treat it as a DB column
  self.ignored_columns = [:status]

  belongs_to :seat_section

  has_many :seat_allocations, dependent: :destroy
  has_many :reservations, through: :seat_allocations
  has_many :waitlist_entries, through: :seat_allocations

  validates :capacity, numericality: { greater_than: 0 }

  # Staff can rename the seat by updating the :label field
  # Example: seat.update(label: "A1")

  # Debug callbacks (kept as is)
  before_validation :debug_before_validation
  after_validation :debug_after_validation
  after_create :debug_after_create
  after_update :debug_after_update

  private

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
