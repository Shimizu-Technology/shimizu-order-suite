# app/models/seat_section.rb

class SeatSection < ApplicationRecord
  apply_default_scope
  
  belongs_to :layout
  has_many :seats, dependent: :destroy
  # Define path to restaurant through associations for tenant isolation
  has_one :restaurant, through: :layout

  # For example, we allow these types:
  VALID_SECTION_TYPES = %w[counter table bar booth patio dining].freeze

  validates :name, presence: true
  validates :capacity, numericality: { greater_than: 0 }, allow_nil: true

  # If you want to enforce only recognized types:
  validates :section_type,
            inclusion: {
              in: VALID_SECTION_TYPES,
              message: "%{value} is not a valid section_type"
            },
            allow_blank: true

  # ---------------------------------------
  # Floor number or label
  # ---------------------------------------
  # If you store floors as an integer:
  validates :floor_number, numericality: {
    only_integer: true, greater_than_or_equal_to: 1
  }
  
  # Override with_restaurant_scope for indirect restaurant association
  def self.with_restaurant_scope
    if current_restaurant
      joins(:layout).where(layouts: { restaurant_id: current_restaurant.id })
    else
      all
    end
  end

  # Debug callbacks (optional)
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
