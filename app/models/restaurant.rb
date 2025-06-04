# app/models/restaurant.rb
class Restaurant < ApplicationRecord
  include Broadcastable
  
  # The Restaurant model is the root of the tenant hierarchy
  # It doesn't include TenantScoped because it is the tenant itself
  
  # Define which attributes should trigger broadcasts when changed
  broadcasts_on :name, :description, :address, :phone, :email, :website, :logo, :banner, :admin_settings, :allowed_origins
  # Ensure allowed_origins is always an array
  attribute :allowed_origins, :string, array: true, default: []
  
  # Pushover-related methods
  def pushover_enabled?
    admin_settings&.dig("notification_channels", "orders", "pushover") == true && 
      (admin_settings&.dig("pushover", "user_key").present? || admin_settings&.dig("pushover", "group_key").present?)
  end

  def pushover_recipient_key
    admin_settings&.dig("pushover", "group_key").presence || admin_settings&.dig("pushover", "user_key")
  end

  def send_pushover_notification(message, title = nil, options = {})
    return false unless pushover_enabled?
    
    # Call the job with positional parameters
    SendPushoverNotificationJob.perform_later(
      id, # restaurant_id
      message,
      title: title || name,
      priority: options[:priority] || 0,
      sound: options[:sound],
      url: options[:url],
      url_title: options[:url_title]
    )
    
    true
  end
  
  # Web Push-related methods
  def web_push_enabled?
    admin_settings&.dig("notification_channels", "orders", "web_push") == true && 
      admin_settings&.dig("web_push", "vapid_public_key").present? &&
      admin_settings&.dig("web_push", "vapid_private_key").present?
  end
  
  def web_push_vapid_keys
    {
      public_key: admin_settings&.dig("web_push", "vapid_public_key"),
      private_key: admin_settings&.dig("web_push", "vapid_private_key")
    }
  end
  
  def generate_web_push_vapid_keys!
    # Generate VAPID keys using the web-push gem
    Rails.logger.info("Generating VAPID keys for restaurant #{id}")
    
    begin
      # WebPush.generate_key returns an object with public_key and private_key methods
      vapid_key = WebPush.generate_key
      
      # Create the VAPID keys hash
      vapid_keys = {
        public_key: vapid_key.public_key,
        private_key: vapid_key.private_key
      }
      
      # Log the keys for debugging
      Rails.logger.info("Generated VAPID public key: #{vapid_keys[:public_key]}")
      Rails.logger.info("Public key length: #{vapid_keys[:public_key].length}")
      
      # Update admin_settings
      new_settings = admin_settings || {}
      new_settings["web_push"] ||= {}
      new_settings["web_push"]["vapid_public_key"] = vapid_keys[:public_key]
      new_settings["web_push"]["vapid_private_key"] = vapid_keys[:private_key]
      
      # Save the settings
      update(admin_settings: new_settings)
      
      Rails.logger.info("VAPID keys generated successfully for restaurant #{id}")
      
      vapid_keys
    rescue => e
      Rails.logger.error("Failed to generate VAPID keys for restaurant #{id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise e
    end
  end
  
  def send_web_push_notification(payload, options = {})
    return false unless web_push_enabled?
    
    # Call the job with positional parameters
    SendWebPushNotificationJob.perform_later(
      id, # restaurant_id
      payload,
      options
    )
    
    true
  end
  # Existing associations
  has_many :users,            dependent: :destroy
  has_many :reservations,     dependent: :destroy
  has_many :waitlist_entries, dependent: :destroy
  has_many :menus,            dependent: :destroy
  has_many :operating_hours,  dependent: :destroy
  has_many :special_events,   dependent: :destroy
  has_many :vip_access_codes, dependent: :destroy
  has_many :merchandise_collections, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :locations,        dependent: :destroy
  has_many :fundraisers,      dependent: :destroy

  # Layout-related associations
  has_many :layouts,          dependent: :destroy
  has_many :seat_sections,    through: :layouts
  has_many :seats,            through: :seat_sections

  belongs_to :current_layout, class_name: "Layout", optional: true
  belongs_to :current_menu, class_name: "Menu", optional: true
  belongs_to :current_event, class_name: "SpecialEvent", optional: true
  belongs_to :current_merchandise_collection, class_name: "MerchandiseCollection", optional: true

  validates :time_zone, presence: true
  
  # Convert the time_zone string to an offset string for Time.new()
  # This is used by AvailabilityService to create datetime objects
  def timezone_offset
    return "+00:00" if time_zone.blank?
    
    begin
      tz = ActiveSupport::TimeZone[time_zone]
      offset = tz.now.strftime("%:z")
      Rails.logger.debug("Timezone offset for #{time_zone}: #{offset}")
      return offset
    rescue => e
      Rails.logger.error("Error getting timezone offset for #{time_zone}: #{e.message}")
      return "+00:00" # Default to UTC if there's an error
    end
  end
  
  # Returns the default reservation duration in minutes
  # Used by AvailabilityService to calculate end times for reservations
  def reservation_duration
    default_reservation_length || 60
  end

  validates :default_reservation_length,
            numericality: { only_integer: true, greater_than: 0 }
            
  # Validate reservation configuration in admin_settings
  validate :validate_reservation_settings

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

  # Location-related methods
  def default_location
    locations.find_by(is_default: true)
  end
  
  def active_locations
    locations.where(is_active: true)
  end
  
  def has_multiple_locations?
    locations.count > 1
  end
  
  def set_default_location(location_id)
    location = locations.find(location_id)
    location.make_default!
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

  #--------------------------------------------------------------------------
  # Helper if you only want seats from the "active" layout:
  #--------------------------------------------------------------------------
  # This method is public so it can be called from controllers
  def current_seats
    return [] unless current_layout
    current_layout.seat_sections.includes(:seats).flat_map(&:seats)
  end
  
  # Get seats for a specific location if a layout is associated with that location
  def location_seats(location_id)
    return current_seats unless location_id.present?
    
    # Find the location
    location = locations.find_by(id: location_id)
    return current_seats unless location
    
    # Use the current_layout_id if it exists, otherwise fall back to finding any layout for this location
    if location.current_layout_id.present?
      location_layout = layouts.find_by(id: location.current_layout_id)
      if location_layout
        Rails.logger.info "Using location's current layout (ID: #{location_layout.id}) for location '#{location.name}' (ID: #{location_id})"
        return location_layout.seat_sections.includes(:seats).flat_map(&:seats)
      end
    end
    
    # Fall back to the first layout associated with this location if no current_layout_id is set
    location_layout = layouts.find_by(location_id: location_id)
    return current_seats unless location_layout
    
    # Return seats from the location's layout
    Rails.logger.info "Using location-specific layout (ID: #{location_layout.id}) for location '#{location.name}' (ID: #{location_id})"
    location_layout.seat_sections.includes(:seats).flat_map(&:seats)
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

  # Format operating hours for display in email templates and other places
  # Returns a formatted string of operating hours or an empty string if no hours are set
  def hours
    formatted_hours = operating_hours.order(:day_of_week).map do |oh|
      next "#{day_name(oh.day_of_week)}: Closed" if oh.closed?
      
      open_time = format_time(oh.open_time)
      close_time = format_time(oh.close_time)
      "#{day_name(oh.day_of_week)}: #{open_time} - #{close_time}"
    end.join(", ")
    
    formatted_hours.presence || ""
  end

  private

  def day_name(day_of_week)
    Date::DAYNAMES[day_of_week].first(3)
  end

  def format_time(time)
    return "" unless time
    time.strftime("%l:%M %p").strip
  end

  def normalize_origin(origin)
    # Remove trailing slash if present
    origin.sub(/\/$/, "")
  end

  #--------------------------------------------------------------------------
  # Reservation Configuration Methods
  #--------------------------------------------------------------------------
  # These methods provide access to reservation-related settings
  # with appropriate defaults if not set
  public
  
  # Returns the default duration for a reservation in minutes
  def reservation_duration
    admin_settings&.dig('reservations', 'duration_minutes').presence || default_reservation_length || 60
  end
  
  # Returns the turnaround time between reservations in minutes
  def turnaround_time
    admin_settings&.dig('reservations', 'turnaround_minutes').presence || 15
  end
  
  # Returns the overlap window for checking reservation availability in minutes
  def reservation_overlap_window
    admin_settings&.dig('reservations', 'overlap_window_minutes').presence || 120
  end
  
  # Returns the interval for generating time slots in minutes
  def reservation_time_slot_interval
    admin_settings&.dig('reservations', 'time_slot_interval').presence || time_slot_interval || 30
  end
  
  # Returns the maximum party size allowed for reservations
  def max_party_size
    admin_settings&.dig('reservations', 'max_party_size').presence || 20
  end
  
  # Updates reservation configuration settings
  def update_reservation_settings(settings = {})
    new_settings = admin_settings || {}
    new_settings['reservations'] ||= {}
    
    # Update specific reservation settings
    new_settings['reservations']['duration_minutes'] = settings[:duration_minutes] if settings.key?(:duration_minutes)
    new_settings['reservations']['turnaround_minutes'] = settings[:turnaround_minutes] if settings.key?(:turnaround_minutes)
    new_settings['reservations']['overlap_window_minutes'] = settings[:overlap_window_minutes] if settings.key?(:overlap_window_minutes)
    new_settings['reservations']['time_slot_interval'] = settings[:time_slot_interval] if settings.key?(:time_slot_interval)
    new_settings['reservations']['max_party_size'] = settings[:max_party_size] if settings.key?(:max_party_size)
    
    # Save changes
    update(admin_settings: new_settings)
  end
  
  # Validates that reservation settings are within acceptable ranges
  def validate_reservation_settings
    # Skip validation if admin_settings is nil or reservations is nil
    return unless admin_settings&.key?('reservations')
    
    reservations = admin_settings['reservations']
    
    # Validate duration_minutes (must be positive integer)
    if reservations.key?('duration_minutes')
      duration = reservations['duration_minutes']
      unless duration.is_a?(Integer) && duration > 0 && duration <= 360 # Max 6 hours
        errors.add(:admin_settings, "reservation duration must be a positive integer between 1 and 360 minutes")
      end
    end
    
    # Validate turnaround_minutes (must be non-negative integer)
    if reservations.key?('turnaround_minutes')
      turnaround = reservations['turnaround_minutes']
      unless turnaround.is_a?(Integer) && turnaround >= 0 && turnaround <= 120 # Max 2 hours
        errors.add(:admin_settings, "turnaround time must be a non-negative integer between 0 and 120 minutes")
      end
    end
    
    # Validate overlap_window_minutes (must be positive integer)
    if reservations.key?('overlap_window_minutes')
      overlap = reservations['overlap_window_minutes']
      unless overlap.is_a?(Integer) && overlap > 0 && overlap <= 480 # Max 8 hours
        errors.add(:admin_settings, "overlap window must be a positive integer between 1 and 480 minutes")
      end
    end
    
    # Validate time_slot_interval (must be positive integer and be one of 15, 30, 60)
    if reservations.key?('time_slot_interval')
      interval = reservations['time_slot_interval']
      unless interval.is_a?(Integer) && [15, 30, 60].include?(interval)
        errors.add(:admin_settings, "time slot interval must be 15, 30, or 60 minutes")
      end
    end
    
    # Validate max_party_size (must be positive integer)
    if reservations.key?('max_party_size')
      max_size = reservations['max_party_size']
      unless max_size.is_a?(Integer) && max_size > 0 && max_size <= 100 # Max 100 people
        errors.add(:admin_settings, "maximum party size must be a positive integer between 1 and 100")
      end
    end
  end
end
