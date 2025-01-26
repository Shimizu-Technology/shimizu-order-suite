# app/models/restaurant.rb
class Restaurant < ApplicationRecord
  # Existing associations
  has_many :users,            dependent: :destroy
  has_many :reservations,     dependent: :destroy
  has_many :waitlist_entries, dependent: :destroy
  has_many :menus,            dependent: :destroy
  has_many :operating_hours, dependent: :destroy
  has_many :special_events,   dependent: :destroy

  # Layout-related associations
  has_many :layouts,          dependent: :destroy
  has_many :seat_sections,    through: :layouts
  has_many :seats,            through: :seat_sections

  belongs_to :current_layout, class_name: "Layout", optional: true

  validates :time_zone, presence: true

  validates :default_reservation_length, 
            numericality: { only_integer: true, greater_than: 0 }

  #--------------------------------------------------------------------------
  # Example helper if you only want seats from the "active" layout:
  #--------------------------------------------------------------------------
  def current_seats
    return [] unless current_layout
    current_layout.seat_sections.includes(:seats).flat_map(&:seats)
  end
end
