class SpecialEventsController < ApplicationController
  before_action :authorize_request
  before_action :set_restaurant, only: [:index]

  # GET /restaurants/:restaurant_id/special_events
  def index
    @special_events = @restaurant.special_events
    render json: @special_events
  end

  private

  def set_restaurant
    @restaurant = Restaurant.find(params[:restaurant_id])
  end
  
  # Override the method from RestaurantScope concern
  # This endpoint is public and doesn't require a user's restaurant context
  # since we're explicitly setting the restaurant from params
  def public_endpoint?
    action_name == 'index'
  end
end
