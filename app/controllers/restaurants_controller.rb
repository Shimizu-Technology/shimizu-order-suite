# app/controllers/restaurants_controller.rb
class RestaurantsController < ApplicationController
  before_action :authorize_request, except: [:show]
  before_action :set_restaurant, only: [:show, :update, :destroy]
  
  # Override public_endpoint? to mark index, show, update, and toggle_vip_mode as public endpoints
  def public_endpoint?
    action_name.in?(['index', 'show', 'update', 'toggle_vip_mode'])
  end

  # GET /restaurants
  def index
    if current_user.role == "super_admin"
      @restaurants = Restaurant.all
    else
      @restaurants = Restaurant.where(id: current_user.restaurant_id)
    end

    render json: @restaurants.map { |r| restaurant_json(r) }
  end

  # GET /restaurants/:id
  def show
    # Skip authorization check for public access
    if current_user.present?
      unless current_user.role == "super_admin" || current_user.restaurant_id == @restaurant.id
        return render json: { error: "Forbidden" }, status: :forbidden
      end
    end

    render json: restaurant_json(@restaurant)
  end

  # POST /restaurants
  def create
    unless current_user.role == "super_admin"
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    @restaurant = Restaurant.new(restaurant_params)
    if @restaurant.save
      render json: restaurant_json(@restaurant), status: :created
    else
      render json: { errors: @restaurant.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /restaurants/:id
  def update
    unless current_user.role.in?(%w[admin super_admin]) || current_user.restaurant_id == @restaurant.id
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    # Handle file uploads
    if params[:hero_image].present?
      file = params[:hero_image]
      ext = File.extname(file.original_filename)
      new_filename = "hero_#{@restaurant.id}_#{Time.now.to_i}#{ext}"
      public_url = S3Uploader.upload(file, new_filename)
      
      # Initialize admin_settings if it doesn't exist
      @restaurant.admin_settings ||= {}
      @restaurant.admin_settings['hero_image_url'] = public_url
    end

    if params[:spinner_image].present?
      file = params[:spinner_image]
      ext = File.extname(file.original_filename)
      new_filename = "spinner_#{@restaurant.id}_#{Time.now.to_i}#{ext}"
      public_url = S3Uploader.upload(file, new_filename)
      
      # Initialize admin_settings if it doesn't exist
      @restaurant.admin_settings ||= {}
      @restaurant.admin_settings['spinner_image_url'] = public_url
    end

    if @restaurant.update(restaurant_params)
      render json: restaurant_json(@restaurant)
    else
      render json: { errors: @restaurant.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /restaurants/:id
  def destroy
    unless current_user.role == "super_admin"
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    @restaurant.destroy
    head :no_content
  end

  # PATCH /restaurants/:id/toggle_vip_mode
  def toggle_vip_mode
    @restaurant = Restaurant.unscoped.find(params[:id])
    unless current_user.role.in?(%w[admin super_admin]) || current_user.restaurant_id == @restaurant.id
      return render json: { error: "Forbidden" }, status: :forbidden
    end
    
    # Extract vip_enabled from params, handling both formats
    vip_enabled = if params[:restaurant] && params[:restaurant][:vip_enabled].present?
                    params[:restaurant][:vip_enabled]
                  else
                    params[:vip_enabled]
                  end
    
    if @restaurant.update(vip_enabled: vip_enabled)
      render json: { 
        success: true, 
        vip_enabled: @restaurant.vip_enabled,
        restaurant: restaurant_json(@restaurant)
      }
    else
      render json: { 
        success: false, 
        errors: @restaurant.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end

  # PATCH /restaurants/:id/set_current_event
  def set_current_event
    @restaurant = Restaurant.find(params[:id])
    unless current_user.role.in?(%w[admin super_admin]) || current_user.restaurant_id == @restaurant.id
      return render json: { error: "Forbidden" }, status: :forbidden
    end
    
    event_id = params[:event_id]
    
    if event_id.present?
      event = @restaurant.special_events.find_by(id: event_id)
      
      if event.nil?
        return render json: { error: "Event not found" }, status: :not_found
      end
      
      if @restaurant.update(current_event_id: event.id)
        render json: restaurant_json(@restaurant)
      else
        render json: { errors: @restaurant.errors.full_messages }, status: :unprocessable_entity
      end
    else
      # Clear the current event
      if @restaurant.update(current_event_id: nil)
        render json: restaurant_json(@restaurant)
      else
        render json: { errors: @restaurant.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end
  
  private

  def set_restaurant
    @restaurant = Restaurant.find(params[:id])
  end

  def restaurant_params
    permitted = params.require(:restaurant).permit(
      :name,
      :address,
      :phone_number,
      :layout_type,
      :current_layout_id,
      :default_reservation_length,
      :time_slot_interval,
      :time_zone,
      :contact_email,
      :custom_pickup_location,
      admin_settings: {},
      allowed_origins: []
    )
    
    # Handle allowed_origins as a special case if it's a string
    if params[:restaurant][:allowed_origins].is_a?(String)
      permitted[:allowed_origins] = params[:restaurant][:allowed_origins].split(',').map(&:strip)
    end
    
    permitted
  end

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
