# app/models/restaurant.rb
class Restaurant < ApplicationRecord
  # Ensure allowed_origins is always an array
  attribute :allowed_origins, :string, array: true, default: []
  # Existing associations
  has_many :users,            dependent: :destroy
  has_many :reservations,     dependent: :destroy
  has_many :waitlist_entries, dependent: :destroy
  has_many :menus,            dependent: :destroy
  has_many :operating_hours,  dependent: :destroy
  has_many :special_events,   dependent: :destroy
  has_many :vip_access_codes, dependent: :destroy
  has_many :merchandise_collections, dependent: :destroy

  # Layout-related associations
  has_many :layouts,          dependent: :destroy
  has_many :seat_sections,    through: :layouts
  has_many :seats,            through: :seat_sections

  belongs_to :current_layout, class_name: "Layout", optional: true
  belongs_to :current_menu, class_name: "Menu", optional: true
  belongs_to :current_event, class_name: "SpecialEvent", optional: true
  belongs_to :current_merchandise_collection, class_name: "MerchandiseCollection", optional: true

  validates :time_zone, presence: true

  validates :default_reservation_length,
            numericality: { only_integer: true, greater_than: 0 }

  # VIP-related methods
  def vip_only_checkout?
    vip_enabled || current_event&.vip_only?
  end

  def validate_vip_code(code)
    return true unless vip_only_checkout?

    # Check directly associated codes first
    vip_code = vip_access_codes.find_by(code: code)
    return true if vip_code && vip_code.available?

    # Fall back to event codes
    current_event&.valid_vip_code?(code)
  end

  def use_vip_code!(code)
    return unless vip_only_checkout?

    # Try to find and use directly associated code
    vip_code = vip_access_codes.find_by(code: code)
    return vip_code.use! if vip_code && vip_code.available?

    # Fall back to event-based code
    current_event&.use_vip_code!(code)
  end

  def set_current_event(event_id)
    event = self.special_events.find(event_id)
    update(current_event_id: event.id)
  end

  # Helper methods for allowed_origins
  def add_allowed_origin(origin)
    return if origin.blank?

    # Normalize the origin (remove trailing slashes, etc.)
    normalized_origin = normalize_origin(origin)

    # Add to allowed_origins if not already present
    unless allowed_origins.include?(normalized_origin)
      self.allowed_origins = (allowed_origins || []) + [ normalized_origin ]
      save
    end
  end

  def remove_allowed_origin(origin)
    return if origin.blank?

    normalized_origin = normalize_origin(origin)

    if allowed_origins.include?(normalized_origin)
      self.allowed_origins = allowed_origins - [ normalized_origin ]
      save
    end
  end

  private

  def normalize_origin(origin)
    # Remove trailing slash if present
    origin.sub(/\/$/, "")
  end

  #--------------------------------------------------------------------------
  # Helper if you only want seats from the "active" layout:
  #--------------------------------------------------------------------------
  # Make this method public so it can be called from controllers
  def current_seats
    return [] unless current_layout
    current_layout.seat_sections.includes(:seats).flat_map(&:seats)
  end

  #--------------------------------------------------------------------------
  # Helper to set the active menu:
  #--------------------------------------------------------------------------
  def set_active_menu(menu_id)
    menu = self.menus.find(menu_id)
    update(current_menu_id: menu.id)
  end

  #--------------------------------------------------------------------------
  # Helper to set the active merchandise collection:
  #--------------------------------------------------------------------------
  def set_active_merchandise_collection(collection_id)
    collection = self.merchandise_collections.find(collection_id)
    update(current_merchandise_collection_id: collection.id)
  end
end
