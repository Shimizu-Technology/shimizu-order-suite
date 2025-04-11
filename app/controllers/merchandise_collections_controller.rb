class MerchandiseCollectionsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request, only: [:set_active]
  
  # GET /merchandise_collections
  def index
    result = merchandise_collection_service.list_collections(params)
    
    if result[:success]
      render json: result[:collections]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # GET /merchandise_collections/1
  def show
    result = merchandise_collection_service.get_collection(params[:id])
    
    if result[:success]
      render json: result[:collection], include_items: true
    else
      render json: { errors: result[:errors] }, status: result[:status] || :not_found
    end
  end
  
  # POST /merchandise_collections
  def create
    result = merchandise_collection_service.create_collection(merchandise_collection_params, current_user)
    
    if result[:success]
      render json: result[:collection], status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # PATCH/PUT /merchandise_collections/1
  def update
    result = merchandise_collection_service.update_collection(params[:id], merchandise_collection_params, current_user)
    
    if result[:success]
      render json: result[:collection]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # DELETE /merchandise_collections/1
  def destroy
    result = merchandise_collection_service.delete_collection(params[:id], current_user)
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # POST /merchandise_collections/:id/set_active
  def set_active
    result = merchandise_collection_service.set_active_collection(params[:id], current_user)
    
    if result[:success]
      render json: {
        message: result[:message],
        current_merchandise_collection_id: result[:current_merchandise_collection_id]
      }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  private
  
  def merchandise_collection_params
    params.require(:merchandise_collection).permit(:name, :description, :active)
  end
  
  def merchandise_collection_service
    @merchandise_collection_service ||= MerchandiseCollectionService.new(current_restaurant, analytics)
  end
end
