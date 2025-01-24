# app/models/seat_section.rb

class SeatSection < ApplicationRecord
  belongs_to :layout
  has_many :seats, dependent: :destroy

  # For example, we allow these types:
  VALID_SECTION_TYPES = %w[counter table bar booth].freeze

  validates :name, presence: true
  validates :capacity, numericality: { greater_than: 0 }, allow_nil: true

  # If you want to enforce only recognized types:
  validates :section_type,
            inclusion: {
              in: VALID_SECTION_TYPES,
              message: "%{value} is not a valid section_type"
            },
            allow_blank: true

  # Debug callbacks (optional, as you have them)
  before_validation :debug_before_validation
  after_validation :debug_after_validation
  after_create :debug_after_create
  after_update :debug_after_update

  private

  def debug_before_validation
    Rails.logger.debug "SeatSection#before_validation => #{attributes.inspect}"
  end

  def debug_after_validation
    if errors.any?
      Rails.logger.debug "SeatSection#after_validation => ERRORS: #{errors.full_messages}"
    else
      Rails.logger.debug "SeatSection#after_validation => no validation errors"
    end
  end

  def debug_after_create
    Rails.logger.debug "SeatSection#after_create => record created: #{attributes.inspect}"
  end

  def debug_after_update
    Rails.logger.debug "SeatSection#after_update => record updated: #{attributes.inspect}"
  end
end
