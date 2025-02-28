# app/models/restaurant.rb
class Restaurant < ApplicationRecord
  # Ensure allowed_origins is always an array
  attribute :allowed_origins, :string, array: true, default: []
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
            
  # Helper methods for allowed_origins
  def add_allowed_origin(origin)
    return if origin.blank?
    
    # Normalize the origin (remove trailing slashes, etc.)
    normalized_origin = normalize_origin(origin)
    
    # Add to allowed_origins if not already present
    unless allowed_origins.include?(normalized_origin)
      self.allowed_origins = (allowed_origins || []) + [normalized_origin]
      save
    end
  end
  
  def remove_allowed_origin(origin)
    return if origin.blank?
    
    normalized_origin = normalize_origin(origin)
    
    if allowed_origins.include?(normalized_origin)
      self.allowed_origins = allowed_origins - [normalized_origin]
      save
    end
  end
  
  private
  
  def normalize_origin(origin)
    # Remove trailing slash if present
    origin.sub(/\/$/, '')
  end

  #--------------------------------------------------------------------------
  # Helper if you only want seats from the "active" layout:
  #--------------------------------------------------------------------------
  # Make this method public so it can be called from controllers
  def current_seats
    return [] unless current_layout
    current_layout.seat_sections.includes(:seats).flat_map(&:seats)
  end
end
