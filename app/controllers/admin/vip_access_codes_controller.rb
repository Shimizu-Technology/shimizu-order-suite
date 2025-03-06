class Admin::VipAccessCodesController < ApplicationController
  before_action :authorize_request
  before_action :require_admin
  
  def index
    @restaurant = current_user.restaurant
    
    # Filter by special event if provided
    if params[:special_event_id].present?
      @special_event = @restaurant.special_events.find_by(id: params[:special_event_id])
      @vip_codes = @special_event ? @special_event.vip_access_codes : []
    else
      # Otherwise, get all codes for the restaurant
      @vip_codes = @restaurant.vip_access_codes
    end
    
    render json: @vip_codes
  end
  
  def create
    @restaurant = current_user.restaurant
    
    options = {
      name: params[:name],
      prefix: params[:prefix],
      max_uses: params[:max_uses].present? ? params[:max_uses].to_i : nil,
    }
    
    # Add special event reference if needed
    if params[:special_event_id].present?
      @special_event = @restaurant.special_events.find_by(id: params[:special_event_id])
      options[:special_event_id] = @special_event.id if @special_event
    end
    
    if params[:batch]
      # Generate multiple individual codes
      count = params[:count].to_i || 1
      @vip_codes = VipCodeGenerator.generate_codes(@restaurant, count, options)
      render json: @vip_codes
    else
      # Generate a single group code
      @vip_code = VipCodeGenerator.generate_group_code(@restaurant, options)
      render json: @vip_code
    end
  end
  
  def update
    @vip_code = current_user.restaurant.vip_access_codes.find(params[:id])
    
    if @vip_code.update(vip_code_params)
      render json: @vip_code
    else
      render json: { errors: @vip_code.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def destroy
    @vip_code = current_user.restaurant.vip_access_codes.find(params[:id])
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
end
