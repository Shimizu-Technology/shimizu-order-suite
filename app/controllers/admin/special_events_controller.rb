# app/controllers/admin/special_events_controller.rb
class Admin::SpecialEventsController < ApplicationController
  before_action :authorize_request
  before_action :require_admin
  before_action :set_special_event, only: [:show, :update, :destroy, :set_as_current]
  
  # Mark index, create, and set_as_current as public endpoints that don't require restaurant context
  def public_endpoint?
    ['index', 'create', 'set_as_current'].include?(action_name)
  end
  
  # GET /admin/special_events
  def index
    if current_restaurant
      @special_events = current_restaurant.special_events
    else
      # If no restaurant context, return all special events
      # This is useful for super_admin users who want to see all events
      @special_events = SpecialEvent.all
    end
    render json: @special_events
  end
  
  # GET /admin/special_events/:id
  def show
    restaurant = current_restaurant
    
    if restaurant.nil?
      render json: { error: "Restaurant not found" }, status: :unprocessable_entity
      return
    end
    
    render json: @special_event
  end
  
  # POST /admin/special_events
  def create
    # Find the restaurant from params if current_restaurant is nil
    restaurant = current_restaurant
    
    if restaurant.nil? && params[:restaurant_id].present?
      restaurant = Restaurant.find_by(id: params[:restaurant_id])
    end
    
    if restaurant.nil?
      render json: { error: "Restaurant not found" }, status: :unprocessable_entity
      return
    end
    
    @special_event = restaurant.special_events.new(special_event_params)
    
    if @special_event.save
      render json: @special_event, status: :created
    else
      render json: { errors: @special_event.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  # PATCH/PUT /admin/special_events/:id
  def update
    restaurant = current_restaurant
    
    if restaurant.nil?
      render json: { error: "Restaurant not found" }, status: :unprocessable_entity
      return
    end
    
    if @special_event.update(special_event_params)
      render json: @special_event
    else
      render json: { errors: @special_event.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  # DELETE /admin/special_events/:id
  def destroy
    restaurant = current_restaurant
    
    if restaurant.nil?
      render json: { error: "Restaurant not found" }, status: :unprocessable_entity
      return
    end
    
    # If this is the current event for the restaurant, clear it
    if restaurant.current_event_id == @special_event.id
      restaurant.update(current_event_id: nil)
    end
    
    @special_event.destroy
    head :no_content
  end
  
  # POST /admin/special_events/:id/set_as_current
  def set_as_current
    restaurant = current_restaurant
    
    if restaurant.nil? && params[:restaurant_id].present?
      restaurant = Restaurant.find_by(id: params[:restaurant_id])
    end
    
    if restaurant.nil?
      render json: { error: "Restaurant not found" }, status: :unprocessable_entity
      return
    end
    
    if restaurant.update(current_event_id: @special_event.id)
      render json: { success: true, message: "Event set as current" }
    else
      render json: { errors: restaurant.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  private
  
  def set_special_event
    restaurant = current_restaurant
    
    if restaurant.nil? && params[:restaurant_id].present?
      restaurant = Restaurant.find_by(id: params[:restaurant_id])
    end
    
    if restaurant.nil?
      render json: { error: "Restaurant not found" }, status: :unprocessable_entity
      return
    end
    
    @special_event = restaurant.special_events.find_by(id: params[:id])
    
    unless @special_event
      render json: { error: "Special event not found" }, status: :not_found
      return
    end
  end
  
  def special_event_params
    # The special_events table doesn't have a name column, so we'll use description instead
    # If name is provided, we'll use it as the description
    event_params = params.require(:special_event).permit(
      :description, 
      :event_date, 
      :start_time, 
      :end_time, 
      :max_capacity,
      :vip_only_checkout,
      :code_prefix
    )
    
    # If name is provided but description is not, use name as description
    if params[:special_event][:name].present? && event_params[:description].blank?
      event_params[:description] = params[:special_event][:name]
    end
    
    event_params
  end
  
  def require_admin
    unless current_user&.role.in?(%w[admin super_admin])
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end
  
  def current_restaurant
    @current_restaurant ||= if current_user.role == 'super_admin' && params[:restaurant_id].present?
      Restaurant.find_by(id: params[:restaurant_id])
    else
      current_user.restaurant
    end
  end
end
