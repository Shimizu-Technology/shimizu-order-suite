# app/models/restaurant.rb
class Restaurant < ApplicationRecord
  include Broadcastable
  
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

  #--------------------------------------------------------------------------
  # Helper if you only want seats from the "active" layout:
  #--------------------------------------------------------------------------
  # This method is public so it can be called from controllers
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

  private

  def normalize_origin(origin)
    # Remove trailing slash if present
    origin.sub(/\/$/, "")
  end
end
