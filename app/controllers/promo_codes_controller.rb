# app/controllers/promo_codes_controller.rb
class PromoCodesController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request, except: [:index, :show]
  
  # Override global_access_permitted to allow public access to index and show
  def global_access_permitted?
    action_name.in?(["index", "show"])
  end
  
  # GET /promo_codes
  def index
    result = promo_code_service.list_promo_codes(current_user)
    
    if result[:success]
      render json: result[:promo_codes]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # GET /promo_codes/:id or /promo_codes/:code
  def show
    result = promo_code_service.get_promo_code(params[:id])
    
    if result[:success]
      render json: result[:promo_code]
    else
      render json: { error: result[:errors].first }, status: result[:status] || :not_found
    end
  end
  
  # POST /promo_codes (admin only)
  def create
    result = promo_code_service.create_promo_code(promo_code_params, current_user)
    
    if result[:success]
      render json: result[:promo_code], status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # PATCH/PUT /promo_codes/:id
  def update
    result = promo_code_service.update_promo_code(params[:id], promo_code_params, current_user)
    
    if result[:success]
      render json: result[:promo_code]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # DELETE /promo_codes/:id
  def destroy
    result = promo_code_service.delete_promo_code(params[:id], current_user)
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  private
  
  def promo_code_params
    params.require(:promo_code).permit(:code, :discount_percent, :valid_from, :valid_until,
                                       :max_uses, :current_uses, :restaurant_id)
  end
  
  def promo_code_service
    @promo_code_service ||= PromoCodeService.new(current_restaurant, analytics)
  end
end
