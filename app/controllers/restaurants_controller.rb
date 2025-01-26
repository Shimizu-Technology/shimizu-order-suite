# app/controllers/restaurants_controller.rb
class RestaurantsController < ApplicationController
  before_action :authorize_request
  before_action :set_restaurant, only: [:show, :update, :destroy]

  # GET /restaurants
  def index
    # If super_admin => see all, otherwise only the current user's single restaurant
    if current_user.role == "super_admin"
      @restaurants = Restaurant.all
    else
      @restaurants = Restaurant.where(id: current_user.restaurant_id)
    end

    # Return an array of restaurants in JSON
    render json: @restaurants.map { |r| restaurant_json(r) }
  end

  # GET /restaurants/:id
  def show
    # Staff/admin can only see their own restaurant (unless super_admin)
    unless current_user.role == "super_admin" || current_user.restaurant_id == @restaurant.id
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    render json: restaurant_json(@restaurant)
  end

  # POST /restaurants
  def create
    # Typically only super_admin can create new restaurants, but adjust as needed
    unless current_user.role.in?(%w[super_admin])
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
    # Let super_admin or staff/admin of that restaurant update it
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
    # Typically only super_admin can delete a restaurant
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
    # Only permit the fields that actually exist in your DB schema
    params.require(:restaurant).permit(
      :name,
      :address,
      :layout_type,
      :current_layout_id,
      :opening_time,
      :closing_time,
      :default_reservation_length,
      :time_slot_interval,
      :time_zone,            # If you store a time_zone
      admin_settings: {}     # JSONB field for additional settings
    )
  end

  def restaurant_json(restaurant)
    {
      id:                         restaurant.id,
      name:                       restaurant.name,
      address:                    restaurant.address,
      layout_type:                restaurant.layout_type,
      current_layout_id:          restaurant.current_layout_id,
      opening_time:               restaurant.opening_time,
      closing_time:               restaurant.closing_time,
      default_reservation_length: restaurant.default_reservation_length,
      time_slot_interval:         restaurant.time_slot_interval,
      time_zone:                  restaurant.time_zone,
      admin_settings:             restaurant.admin_settings
    }
  end
end
