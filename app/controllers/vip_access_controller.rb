class VipAccessController < ApplicationController
  before_action :authorize_request, except: [:validate_code]
  before_action :set_restaurant, only: [:validate_code]
  before_action :set_current_restaurant, except: [:validate_code]
  before_action :set_vip_code, only: [:deactivate_code, :update_code, :archive_code]
  
  # Override public_endpoint? to mark codes and generate_codes as public endpoints
  def public_endpoint?
    action_name.in?(['codes', 'generate_codes', 'deactivate_code', 'update_code', 'validate_code', 'archive_code', 'code_usage'])
  end
  
  def validate_code
    code = params[:code]
    
    if code.blank?
      return render json: { valid: false, message: "VIP code is required" }, status: :bad_request
    end
    
    # Check if the restaurant has VIP-only checkout enabled
    unless @restaurant.vip_only_checkout?
      return render json: { valid: true, message: "VIP access not required" }
    end
    
    # Find the VIP code
    vip_code = @restaurant.vip_access_codes.find_by(code: code)
    
    # Check if the code exists and is available
    if vip_code && vip_code.available?
      render json: { valid: true, message: "Valid VIP code" }
    else
      # Provide a more specific error message if the code exists but has reached its usage limit
      if vip_code && vip_code.max_uses && vip_code.current_uses >= vip_code.max_uses
        render json: { valid: false, message: "This VIP code has reached its maximum usage limit" }, status: :unauthorized
      else
        render json: { valid: false, message: "Invalid VIP code" }, status: :unauthorized
      end
    end
  end
  
  # GET /vip_access/codes
  def codes
    # By default, don't show archived codes unless explicitly requested
    if params[:include_archived] == 'true'
      @codes = @restaurant.vip_access_codes
    else
      @codes = @restaurant.vip_access_codes.where(archived: false)
    end
    
    # Sort by creation date (newest first) by default
    @codes = @codes.order(created_at: :desc)
    
    render json: @codes
  end
  
  # POST /vip_access/generate_codes
  def generate_codes
    # Check if the user has permission
    unless current_user.role.in?(%w[admin super_admin]) || current_user.restaurant_id == @restaurant.id
      return render json: { error: "Forbidden" }, status: :forbidden
    end
    
    options = {
      name: params[:name],
      prefix: params[:prefix],
      max_uses: params[:max_uses].present? ? params[:max_uses].to_i : nil,
    }
    
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
  
  # DELETE /vip_access/codes/:id
  def deactivate_code
    @vip_code.update!(is_active: false)
    render json: { message: "VIP code deactivated successfully" }
  end
  
  # PATCH /vip_access/codes/:id
  def update_code
    # Check if the params are nested under vip_code or directly in the params
    if params[:vip_code].present?
      vip_code_params = params.require(:vip_code).permit(:name, :max_uses, :expires_at, :is_active)
    else
      vip_code_params = params.permit(:name, :max_uses, :expires_at, :is_active)
    end
    
    @vip_code.update!(vip_code_params)
    render json: @vip_code
  end
  
  # POST /vip_access/codes/:id/archive
  def archive_code
    @vip_code.update!(archived: true, is_active: false)
    render json: { message: "VIP code archived successfully" }
  end
  
  # GET /vip_access/codes/:id/usage
  def code_usage
    @vip_code = VipAccessCode.find(params[:id])
    
    # Ensure the VIP code belongs to the current restaurant
    unless @vip_code.restaurant_id == @restaurant&.id
      render json: { error: "VIP code not found" }, status: :not_found
      return
    end
    
    # Get orders that used this VIP code
    @orders = @vip_code.orders.includes(:user).order(created_at: :desc)
    
    # Prepare the response with code details and order information
    response = {
      code: @vip_code.as_json,
      usage_count: @orders.count,
      orders: @orders.map do |order|
        {
          id: order.id,
          created_at: order.created_at,
          status: order.status,
          total: order.total.to_f,
          customer_name: order.contact_name,
          customer_email: order.contact_email,
          customer_phone: order.contact_phone,
          user: order.user ? { id: order.user.id, name: "#{order.user.first_name} #{order.user.last_name}" } : nil,
          items: order.items.map do |item|
            {
              name: item['name'],
              quantity: item['quantity'],
              price: item['price'].to_f,
              total: (item['price'].to_f * item['quantity'].to_i)
            }
          end
        }
      end
    }
    
    render json: response
  end
  
  private
  
  def set_restaurant
    @restaurant = Restaurant.find(params[:restaurant_id])
  end
  
  def set_current_restaurant
    @restaurant = current_user.restaurant
  end
  
  def set_vip_code
    @vip_code = VipAccessCode.find(params[:id])
    
    # Ensure the VIP code belongs to the current restaurant
    unless @vip_code.restaurant_id == @restaurant&.id
      render json: { error: "VIP code not found" }, status: :not_found
      return
    end
  end
end
