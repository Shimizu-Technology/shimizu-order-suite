class VipAccessController < ApplicationController
  before_action :authorize_request, except: [:validate_code, :validate]
  before_action :set_restaurant
  
  # Override public_endpoint? to mark validate as a public endpoint
  def public_endpoint?
    ['validate', 'validate_code'].include?(action_name)
  end
  
  # POST /restaurants/:restaurant_id/validate_vip_code
  def validate_code
    code = params[:code]
    
    if code.blank?
      render json: { valid: false, message: "VIP code is required" }, status: :unprocessable_entity
      return
    end
    
    # Check if the restaurant has VIP-only checkout enabled
    unless @restaurant.vip_only_checkout?
      render json: { valid: true, message: "VIP access not required for this restaurant" }
      return
    end
    
    # Validate the code against the current event
    if @restaurant.validate_vip_code(code)
      render json: { valid: true, message: "VIP code validated successfully" }
    else
      render json: { valid: false, message: "Invalid VIP code" }, status: :unprocessable_entity
    end
  end
  
  # POST /vip_access/validate
  def validate
    code = params[:code]
    
    if code.blank?
      render json: { valid: false, message: "VIP code is required" }, status: :unprocessable_entity
      return
    end
    
    # Check if the restaurant has VIP-only checkout enabled
    unless @restaurant.vip_only_checkout?
      render json: { valid: true, message: "VIP access not required for this restaurant" }
      return
    end
    
    # Validate the code against the current event
    if @restaurant.validate_vip_code(code)
      render json: { valid: true, message: "VIP code validated successfully" }
    else
      render json: { valid: false, message: "Invalid VIP code" }, status: :unprocessable_entity
    end
  end
  
  private
  
  def set_restaurant
    # For the validate action, the restaurant_id is passed as a query parameter
    if action_name == 'validate'
      @restaurant = Restaurant.find_by(id: params[:restaurant_id])
      if @restaurant.nil?
        render json: { valid: false, message: "Restaurant not found" }, status: :not_found
        return
      end
    else
      # For other actions, the restaurant_id is part of the URL
      begin
        @restaurant = Restaurant.find(params[:restaurant_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Restaurant not found" }, status: :not_found
      end
    end
  end
end
