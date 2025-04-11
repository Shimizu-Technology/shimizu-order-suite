class MerchandiseVariantsController < ApplicationController
  include TenantIsolation
  
  # For index & show, we skip the tenant context check to allow public access
  skip_before_action :set_current_tenant, only: [:index, :show]
  
  # For other actions, require token + admin
  before_action :authorize_request, except: [:index, :show]
  
  # Override global_access_permitted to allow public access to index and show
  def global_access_permitted?
    action_name.in?(["index", "show"])
  end
  
  # GET /merchandise_variants
  def index
    result = merchandise_variant_service.list_variants(params)
    
    if result[:success]
      render json: result[:variants]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # GET /merchandise_variants/1
  def show
    result = merchandise_variant_service.get_variant(params[:id])
    
    if result[:success]
      render json: result[:variant]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :not_found
    end
  end
  
  # POST /merchandise_variants
  def create
    result = merchandise_variant_service.create_variant(merchandise_variant_params, current_user)
    
    if result[:success]
      render json: result[:variant], status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # PATCH/PUT /merchandise_variants/1
  def update
    result = merchandise_variant_service.update_variant(params[:id], merchandise_variant_params, current_user)
    
    if result[:success]
      render json: result[:variant]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # DELETE /merchandise_variants/1
  def destroy
    result = merchandise_variant_service.delete_variant(params[:id], current_user)
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # POST /merchandise_variants/batch_create
  def batch_create
    result = merchandise_variant_service.batch_create_variants(
      params[:merchandise_item_id],
      params[:variants],
      current_user
    )
    
    if result[:success]
      render json: {
        message: result[:message],
        variants: result[:variants]
      }, status: :created
    else
      render json: {
        error: result[:errors].first,
        failed_variants: result[:failed_variants]
      }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # POST /merchandise_variants/:id/add_stock
  def add_stock
    result = merchandise_variant_service.add_stock(
      params[:id],
      params[:quantity].to_i,
      params[:reason],
      current_user
    )
    
    if result[:success]
      render json: {
        message: result[:message],
        new_quantity: result[:new_quantity],
        variant: result[:variant]
      }
    else
      render json: { error: result[:errors].first }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # POST /merchandise_variants/:id/reduce_stock
  def reduce_stock
    result = merchandise_variant_service.reduce_stock(
      params[:id],
      params[:quantity].to_i,
      params[:reason],
      params[:allow_negative] == "true",
      current_user
    )
    
    if result[:success]
      render json: {
        message: result[:message],
        new_quantity: result[:new_quantity],
        variant: result[:variant]
      }
    else
      render json: { error: result[:errors].first }, status: result[:status] || :unprocessable_entity
    end
  end
  
  private
  
  def merchandise_variant_params
    params.require(:merchandise_variant).permit(
      :merchandise_item_id,
      :size,
      :color,
      :price_adjustment,
      :stock_quantity,
      :sku,
      :low_stock_threshold
    )
  end
  
  def merchandise_variant_service
    @merchandise_variant_service ||= MerchandiseVariantService.new(current_restaurant, analytics)
  end
end
