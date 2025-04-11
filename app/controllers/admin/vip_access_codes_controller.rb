class Admin::VipAccessCodesController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request
  before_action :require_admin
  before_action :ensure_tenant_context

  def index
    # Use the VipAccessCodesService to get VIP codes with tenant isolation
    vip_codes = vip_access_codes_service.list_codes(params)
    render json: vip_codes
  end

  def create
    # Use the VipAccessCodesService to create VIP codes with tenant isolation
    result = vip_access_codes_service.create_codes(params)
    render json: result
  end

  def update
    # Use the VipAccessCodesService to update a VIP code with tenant isolation
    result = vip_access_codes_service.update_code(params[:id], vip_code_params)
    
    if result[:success]
      render json: result[:vip_code]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  def destroy
    # Use the VipAccessCodesService to deactivate a VIP code with tenant isolation
    vip_access_codes_service.deactivate_code(params[:id])
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
  
  def vip_access_codes_service
    @vip_access_codes_service ||= VipAccessCodesService.new(current_restaurant)
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
end
