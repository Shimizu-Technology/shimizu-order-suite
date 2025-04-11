# app/controllers/vip_access_controller.rb
class VipAccessController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request, except: [:validate_code]
  
  # Override global_access_permitted to allow certain actions without tenant context
  def global_access_permitted?
    action_name.in?(["validate_code"])
  end
  
  def validate_code
    # For validate_code, we need to get the restaurant from params
    restaurant = Restaurant.find_by(id: params[:restaurant_id])
    
    unless restaurant
      return render json: { valid: false, message: "Restaurant not found" }, status: :not_found
    end
    
    result = vip_access_codes_service(restaurant).validate_code(params[:code], restaurant)
    
    if result[:valid]
      render json: { valid: true, message: result[:message] }
    else
      render json: { valid: false, message: result[:message] }, status: result[:status] || :unauthorized
    end
  end
  
  # GET /vip_access/codes
  def codes
    result = vip_access_codes_service.list_codes(params)
    
    if result[:success]
      render json: result[:codes]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # POST /vip_access/generate_codes
  def generate_codes
    result = vip_access_codes_service.create_codes(params, current_user)
    
    if result[:success]
      render json: result[:vip_codes]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # DELETE /vip_access/codes/:id
  def deactivate_code
    result = vip_access_codes_service.deactivate_code(params[:id])
    
    if result[:success]
      render json: { message: result[:message] }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # PATCH /vip_access/codes/:id
  def update_code
    # Check if the params are nested under vip_code or directly in the params
    if params[:vip_code].present?
      vip_code_params = params.require(:vip_code).permit(:name, :max_uses, :expires_at, :is_active)
    else
      vip_code_params = params.permit(:name, :max_uses, :expires_at, :is_active)
    end
    
    result = vip_access_codes_service.update_code(params[:id], vip_code_params)
    
    if result[:success]
      render json: result[:vip_code]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # POST /vip_access/codes/:id/archive
  def archive_code
    result = vip_access_codes_service.archive_code(params[:id])
    
    if result[:success]
      render json: { message: result[:message] }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # GET /vip_access/codes/:id/usage
  def code_usage
    result = vip_access_codes_service.code_usage(params[:id])
    
    if result[:success]
      render json: result[:usage]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # POST /vip_access/send_code_email
  def send_vip_code_email
    result = vip_access_codes_service.send_vip_code_email(params[:emails], params[:code_id])
    
    if result[:success]
      render json: { message: result[:message] }
    else
      render json: { 
        message: result[:message],
        failed: result[:failed]
      }, status: result[:status] || :internal_server_error
    end
  end
  
  # POST /vip_access/bulk_send_vip_codes
  def bulk_send_vip_codes
    result = vip_access_codes_service.bulk_send_vip_codes(params[:email_list], params)
    
    if result[:success]
      render json: {
        message: result[:message],
        total_recipients: result[:total_recipients],
        batch_count: result[:batch_count],
        one_code_per_batch: result[:one_code_per_batch]
      }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # POST /vip_access/send_existing_vip_codes
  def send_existing_vip_codes
    result = vip_access_codes_service.send_existing_vip_codes(
      params[:email_list],
      params[:code_ids],
      params
    )
    
    if result[:success]
      render json: {
        message: result[:message],
        total_recipients: result[:total_recipients],
        batch_count: result[:batch_count]
      }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # GET /vip_access/search_by_email
  def search_by_email
    result = vip_access_codes_service.search_by_email(params[:email], params)
    
    if result[:success]
      render json: result[:codes]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  private
  
  def vip_access_codes_service(restaurant = nil)
    @vip_access_codes_service ||= VipAccessCodesService.new(restaurant || current_restaurant, analytics)
  end
end
