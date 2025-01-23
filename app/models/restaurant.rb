# app/models/restaurant.rb
class Restaurant < ApplicationRecord
  # Existing associations
  has_many :users,            dependent: :destroy
  has_many :reservations,     dependent: :destroy
  has_many :waitlist_entries, dependent: :destroy
  has_many :menus,            dependent: :destroy

  # Layout-related associations
  has_many :layouts,          dependent: :destroy
  has_many :seat_sections,    through: :layouts
  has_many :seats,            through: :seat_sections

  belongs_to :current_layout, class_name: "Layout", optional: true

  # NEW: we require a time_zone string
  validates :time_zone, presence: true

  #--------------------------------------------------------------------------
  # Example helper if you only want seats from the "active" layout:
  #--------------------------------------------------------------------------
  def current_seats
    return [] unless current_layout
    current_layout.seat_sections.includes(:seats).flat_map(&:seats)
  end
end
