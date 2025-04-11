# app/services/restaurant_service.rb
class RestaurantService
  attr_reader :current_restaurant, :analytics
  
  def initialize(current_restaurant = nil, analytics_service = nil)
    @current_restaurant = current_restaurant
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Get all restaurants (for super_admin) or just the current restaurant (for others)
  def list_restaurants(current_user)
    begin
      if current_user.role == "super_admin"
        restaurants = Restaurant.all
      else
        restaurants = Restaurant.where(id: current_user.restaurant_id)
      end
      
      { success: true, restaurants: restaurants }
    rescue => e
      { success: false, errors: ["Failed to retrieve restaurants: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Get a specific restaurant by ID
  def get_restaurant(id, current_user)
    begin
      restaurant = Restaurant.find_by(id: id)
      
      unless restaurant
        return { success: false, errors: ["Restaurant not found"], status: :not_found }
      end
      
      # Check authorization for non-public access
      if current_user.present?
        unless current_user.role == "super_admin" || current_user.restaurant_id == restaurant.id
          return { success: false, errors: ["Forbidden"], status: :forbidden }
        end
      end
      
      { success: true, restaurant: restaurant }
    rescue => e
      { success: false, errors: ["Failed to retrieve restaurant: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Create a new restaurant (super_admin only)
  def create_restaurant(restaurant_params, current_user)
    begin
      # Only super_admin users can create restaurants
      unless current_user.role == "super_admin"
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      restaurant = Restaurant.new(restaurant_params)
      
      if restaurant.save
        # Track restaurant creation
        analytics.track("restaurant.created", { 
          restaurant_id: restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, restaurant: restaurant, status: :created }
      else
        { success: false, errors: restaurant.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to create restaurant: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Update an existing restaurant
  def update_restaurant(id, restaurant_params, file_params, current_user)
    begin
      restaurant = Restaurant.find_by(id: id)
      
      unless restaurant
        return { success: false, errors: ["Restaurant not found"], status: :not_found }
      end
      
      # Check authorization
      unless current_user.role.in?(%w[admin super_admin]) || current_user.restaurant_id == restaurant.id
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      # Handle file uploads
      if file_params[:hero_image].present?
        file = file_params[:hero_image]
        ext = File.extname(file.original_filename)
        new_filename = "hero_#{restaurant.id}_#{Time.now.to_i}#{ext}"
        public_url = S3Uploader.upload(file, new_filename)
        
        # Initialize admin_settings if it doesn't exist
        restaurant.admin_settings ||= {}
        restaurant.admin_settings["hero_image_url"] = public_url
      end
      
      if file_params[:spinner_image].present?
        file = file_params[:spinner_image]
        ext = File.extname(file.original_filename)
        new_filename = "spinner_#{restaurant.id}_#{Time.now.to_i}#{ext}"
        public_url = S3Uploader.upload(file, new_filename)
        
        # Initialize admin_settings if it doesn't exist
        restaurant.admin_settings ||= {}
        restaurant.admin_settings["spinner_image_url"] = public_url
      end
      
      if restaurant.update(restaurant_params)
        # Track restaurant update
        analytics.track("restaurant.updated", { 
          restaurant_id: restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, restaurant: restaurant }
      else
        { success: false, errors: restaurant.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to update restaurant: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Delete a restaurant (super_admin only)
  def delete_restaurant(id, current_user)
    begin
      # Only super_admin users can delete restaurants
      unless current_user.role == "super_admin"
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      restaurant = Restaurant.find_by(id: id)
      
      unless restaurant
        return { success: false, errors: ["Restaurant not found"], status: :not_found }
      end
      
      if restaurant.destroy
        # Track restaurant deletion
        analytics.track("restaurant.deleted", { 
          restaurant_id: id,
          user_id: current_user.id
        })
        
        { success: true, message: "Restaurant deleted successfully" }
      else
        { success: false, errors: ["Failed to delete restaurant"], status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to delete restaurant: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Toggle VIP mode for a restaurant
  def toggle_vip_mode(id, vip_enabled, current_user)
    begin
      restaurant = Restaurant.unscoped.find_by(id: id)
      
      unless restaurant
        return { success: false, errors: ["Restaurant not found"], status: :not_found }
      end
      
      # Check authorization
      unless current_user.role.in?(%w[admin super_admin]) || current_user.restaurant_id == restaurant.id
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      if restaurant.update(vip_enabled: vip_enabled)
        # Track VIP mode toggle
        analytics.track("restaurant.vip_mode_toggled", { 
          restaurant_id: restaurant.id,
          vip_enabled: restaurant.vip_enabled,
          user_id: current_user.id
        })
        
        { 
          success: true, 
          vip_enabled: restaurant.vip_enabled,
          restaurant: restaurant
        }
      else
        { 
          success: false, 
          errors: restaurant.errors.full_messages,
          status: :unprocessable_entity
        }
      end
    rescue => e
      { success: false, errors: ["Failed to toggle VIP mode: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Set current event for a restaurant
  def set_current_event(id, event_id, current_user)
    begin
      restaurant = Restaurant.find_by(id: id)
      
      unless restaurant
        return { success: false, errors: ["Restaurant not found"], status: :not_found }
      end
      
      # Check authorization
      unless current_user.role.in?(%w[admin super_admin]) || current_user.restaurant_id == restaurant.id
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      if event_id.present?
        event = restaurant.special_events.find_by(id: event_id)
        
        unless event
          return { success: false, errors: ["Event not found"], status: :not_found }
        end
        
        if restaurant.update(current_event_id: event.id)
          # Track setting current event
          analytics.track("restaurant.current_event_set", { 
            restaurant_id: restaurant.id,
            event_id: event.id,
            user_id: current_user.id
          })
          
          { success: true, restaurant: restaurant }
        else
          { success: false, errors: restaurant.errors.full_messages, status: :unprocessable_entity }
        end
      else
        # Clear the current event
        if restaurant.update(current_event_id: nil)
          # Track clearing current event
          analytics.track("restaurant.current_event_cleared", { 
            restaurant_id: restaurant.id,
            user_id: current_user.id
          })
          
          { success: true, restaurant: restaurant }
        else
          { success: false, errors: restaurant.errors.full_messages, status: :unprocessable_entity }
        end
      end
    rescue => e
      { success: false, errors: ["Failed to set current event: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Format restaurant JSON for API responses
  def restaurant_json(restaurant)
    {
      id:                         restaurant.id,
      name:                       restaurant.name,
      address:                    restaurant.address,
      phone_number:               restaurant.phone_number,
      contact_email:              restaurant.contact_email,
      layout_type:                restaurant.layout_type,
      current_layout_id:          restaurant.current_layout_id,
      default_reservation_length: restaurant.default_reservation_length,
      time_slot_interval:         restaurant.time_slot_interval,
      time_zone:                  restaurant.time_zone,
      admin_settings:             restaurant.admin_settings,
      allowed_origins:            restaurant.allowed_origins,
      custom_pickup_location:     restaurant.custom_pickup_location,
      # Social media fields
      facebook_url:               restaurant.facebook_url,
      instagram_url:              restaurant.instagram_url,
      twitter_url:                restaurant.twitter_url,
      # VIP-related fields
      vip_only_checkout:          restaurant.vip_only_checkout?,
      vip_enabled:                restaurant.vip_enabled,
      code_prefix:                restaurant.code_prefix,
      current_event_id:           restaurant.current_event_id,
      # Calculate seat count directly instead of using the private method
      current_seat_count:         restaurant.current_layout ?
                                  restaurant.current_layout.seat_sections.includes(:seats).flat_map(&:seats).count :
                                  0
    }
  end
end
