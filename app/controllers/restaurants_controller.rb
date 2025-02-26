# app/controllers/restaurants_controller.rb
class RestaurantsController < ApplicationController
  before_action :authorize_request
  before_action :set_restaurant, only: [:show, :update, :destroy]

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
    unless current_user.role == "super_admin" || current_user.restaurant_id == @restaurant.id
      return render json: { error: "Forbidden" }, status: :forbidden
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

  private

  def set_restaurant
    @restaurant = Restaurant.find(params[:id])
  end

  def restaurant_params
    permitted = params.require(:restaurant).permit(
      :name,
      :address,
      :layout_type,
      :current_layout_id,
      :default_reservation_length,
      :time_slot_interval,
      :time_zone,
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
      layout_type:                restaurant.layout_type,
      current_layout_id:          restaurant.current_layout_id,
      default_reservation_length: restaurant.default_reservation_length,
      time_slot_interval:         restaurant.time_slot_interval,
      time_zone:                  restaurant.time_zone,
      admin_settings:             restaurant.admin_settings,
      allowed_origins:            restaurant.allowed_origins,
      # Expose seat count so the frontend can pre-fill event max_capacity
      current_seat_count:         restaurant.current_seats.count
    }
  end
end
