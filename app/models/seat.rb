class Seat < ApplicationRecord
  belongs_to :seat_section

  has_many :seat_allocations, dependent: :destroy
  has_many :reservations, through: :seat_allocations
  has_many :waitlist_entries, through: :seat_allocations

  validates :capacity, numericality: { greater_than: 0 }

  # Optional debug callbacks (just removing references to status)
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
