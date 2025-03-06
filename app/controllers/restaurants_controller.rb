# app/controllers/restaurants_controller.rb
class RestaurantsController < ApplicationController
  before_action :authorize_request, except: [:show]
  before_action :set_restaurant, only: [:show, :update, :destroy, :set_current_event, :validate_vip_code, :toggle_vip_mode]
  
  # Override public_endpoint? to mark index, show, update, set_current_event, and validate_vip_code as public endpoints
  def public_endpoint?
    ['index', 'show', 'toggle_vip_mode'].include?(action_name)
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
  
  # PATCH /restaurants/:id/set_current_event
  def set_current_event
    unless current_user.role.in?(%w[admin super_admin]) || current_user.restaurant_id == @restaurant.id
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    event_id = params[:event_id]
    
    if event_id.present?
      # Find the event and make sure it belongs to this restaurant
      event = @restaurant.special_events.find_by(id: event_id)
      
      if event.nil?
        return render json: { error: "Event not found" }, status: :not_found
      end
      
      # Set the current event
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
  
  # POST /restaurants/:id/validate_vip_code
  def validate_vip_code
    code = params[:code]
    
    if code.blank?
      return render json: { valid: false, message: "VIP code is required" }, status: :bad_request
    end
    
    # Check if the restaurant has VIP-only checkout enabled
    unless @restaurant.vip_only_checkout?
      return render json: { valid: true, message: "VIP access not required" }
    end
    
    # Validate the code
    if @restaurant.validate_vip_code(code)
      render json: { valid: true, message: "Valid VIP code" }
    else
      render json: { valid: false, message: "Invalid VIP code" }, status: :unauthorized
    end
  end
  
  # PATCH /restaurants/:id/toggle_vip_mode
  def toggle_vip_mode
    @restaurant = Restaurant.find(params[:id])
    authorize @restaurant, :update?
    
    if @restaurant.update(vip_enabled: params[:vip_only_mode])
      render json: { 
        success: true, 
        vip_only_mode: @restaurant.vip_enabled,
        restaurant: @restaurant
      }
    else
      render json: { 
        success: false, 
        errors: @restaurant.errors.full_messages 
      }, status: :unprocessable_entity
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
      :vip_enabled,
      :code_prefix,
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
      layout_type:                restaurant.layout_type,
      current_layout_id:          restaurant.current_layout_id,
      current_event_id:           restaurant.current_event_id,
      default_reservation_length: restaurant.default_reservation_length,
      time_slot_interval:         restaurant.time_slot_interval,
      time_zone:                  restaurant.time_zone,
      admin_settings:             restaurant.admin_settings,
      allowed_origins:            restaurant.allowed_origins,
      # Calculate seat count directly instead of using the private method
      current_seat_count:         restaurant.current_layout ? 
                                  restaurant.current_layout.seat_sections.includes(:seats).flat_map(&:seats).count : 
                                  0,
      vip_only_checkout:          restaurant.vip_only_checkout?,
      vip_only_mode:              restaurant.vip_enabled,
      code_prefix:                restaurant.code_prefix
    }
  end
end
