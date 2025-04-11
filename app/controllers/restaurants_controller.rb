# app/controllers/restaurants_controller.rb
class RestaurantsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request, except: [:show]
  
  # Override global_access_permitted to allow public access to show
  def global_access_permitted?
    action_name.in?(["show", "toggle_vip_mode", "set_current_event"])
  end
  
  # For toggle_vip_mode and set_current_event, we need special handling
  # since they operate on a specific restaurant that may not be the current tenant
  skip_before_action :set_current_tenant, only: [:toggle_vip_mode, :set_current_event]
  
  # GET /restaurants
  def index
    result = restaurant_service.list_restaurants(current_user)
    
    if result[:success]
      render json: result[:restaurants].map { |r| restaurant_service.restaurant_json(r) }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # GET /restaurants/:id
  def show
    result = restaurant_service.get_restaurant(params[:id], current_user)
    
    if result[:success]
      render json: restaurant_service.restaurant_json(result[:restaurant])
    else
      render json: { errors: result[:errors] }, status: result[:status] || :not_found
    end
  end
  
  # POST /restaurants
  def create
    result = restaurant_service.create_restaurant(restaurant_params, current_user)
    
    if result[:success]
      render json: restaurant_service.restaurant_json(result[:restaurant]), status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # PATCH/PUT /restaurants/:id
  def update
    file_params = {
      hero_image: params[:hero_image],
      spinner_image: params[:spinner_image]
    }
    
    result = restaurant_service.update_restaurant(params[:id], restaurant_params, file_params, current_user)
    
    if result[:success]
      render json: restaurant_service.restaurant_json(result[:restaurant])
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # DELETE /restaurants/:id
  def destroy
    result = restaurant_service.delete_restaurant(params[:id], current_user)
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # PATCH /restaurants/:id/toggle_vip_mode
  def toggle_vip_mode
    # Extract vip_enabled from params, handling both formats
    vip_enabled = if params[:restaurant] && params[:restaurant][:vip_enabled].present?
                    params[:restaurant][:vip_enabled]
                  else
                    params[:vip_enabled]
                  end
    
    result = restaurant_service.toggle_vip_mode(params[:id], vip_enabled, current_user)
    
    if result[:success]
      render json: {
        success: true,
        vip_enabled: result[:vip_enabled],
        restaurant: restaurant_service.restaurant_json(result[:restaurant])
      }
    else
      render json: {
        success: false,
        errors: result[:errors]
      }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # PATCH /restaurants/:id/set_current_event
  def set_current_event
    result = restaurant_service.set_current_event(params[:id], params[:event_id], current_user)
    
    if result[:success]
      render json: restaurant_service.restaurant_json(result[:restaurant])
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  private
  
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
      :facebook_url,
      :instagram_url,
      :twitter_url,
      admin_settings: {},
      allowed_origins: []
    )
    
    # Handle allowed_origins as a special case if it's a string
    if params[:restaurant][:allowed_origins].is_a?(String)
      permitted[:allowed_origins] = params[:restaurant][:allowed_origins].split(",").map(&:strip)
    end
    
    permitted
  end
  
  def restaurant_service
    @restaurant_service ||= RestaurantService.new(current_restaurant, analytics)
  end
end
