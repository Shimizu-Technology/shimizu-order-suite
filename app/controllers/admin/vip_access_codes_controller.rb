# app/controllers/admin/vip_access_codes_controller.rb
class Admin::VipAccessCodesController < ApplicationController
  before_action :authorize_request
  before_action :require_admin
  before_action :set_special_event, only: [:index, :create]
  
  # Mark index and create as public endpoints that don't require restaurant context
  def public_endpoint?
    ['index', 'create'].include?(action_name)
  end
  
  def index
    if @special_event
      @vip_codes = @special_event.vip_access_codes
      render json: @vip_codes
    else
      # If no special event is found, return an empty array
      render json: []
    end
  end
  
  def create
    
    if params[:batch]
      # Generate multiple individual codes
      count = params[:count].to_i
      @vip_codes = VipCodeGenerator.generate_individual_codes(@special_event, count, { name: params[:name] })
      render json: @vip_codes
    else
      # Generate a single group code
      @vip_code = VipCodeGenerator.generate_group_code(
        @special_event, 
        { 
          name: params[:name],
          max_uses: params[:max_uses].present? ? params[:max_uses].to_i : nil
        }
      )
      render json: @vip_code
    end
  end
  
  def update
    @vip_code = current_restaurant.vip_access_codes.find(params[:id])
    
    if @vip_code.update(vip_code_params)
      render json: @vip_code
    else
      render json: { errors: @vip_code.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def destroy
    @vip_code = current_restaurant.vip_access_codes.find(params[:id])
    @vip_code.update(is_active: false)
    
    head :no_content
  end
  
  private
  
  def vip_code_params
    params.require(:vip_code).permit(:name, :max_uses, :expires_at, :is_active)
  end
  
  def require_admin
    unless current_user&.role.in?(%w[admin super_admin])
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end
  
  def set_special_event
    # Find the restaurant from params if current_restaurant is nil
    restaurant = current_restaurant
    
    if restaurant.nil? && params[:restaurant_id].present?
      restaurant = Restaurant.find_by(id: params[:restaurant_id])
    end
    
    if restaurant
      @special_event = restaurant.special_events.find_by(id: params[:special_event_id])
    else
      # If no restaurant context, try to find the special event directly
      # This is useful for super_admin users who want to see all events
      @special_event = SpecialEvent.find_by(id: params[:special_event_id])
    end
  rescue ActiveRecord::RecordNotFound
    @special_event = nil
  end
  
  def current_restaurant
    @current_restaurant ||= if current_user.role == 'super_admin' && params[:restaurant_id].present?
      Restaurant.find_by(id: params[:restaurant_id])
    else
      current_user.restaurant
    end
  end
end
