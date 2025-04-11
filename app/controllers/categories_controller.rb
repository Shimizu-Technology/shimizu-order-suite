# app/controllers/categories_controller.rb
class CategoriesController < ApplicationController
  include TenantIsolation
  
  # No admin requirement here, so all users (or guests) can call index:
  before_action :optional_authorize, only: [:index]
  before_action :authorize_request, only: [:create, :update, :destroy]
  before_action :ensure_tenant_context
  
  # GET /menus/:menu_id/categories
  def index
    categories = category_service.list_categories(params[:menu_id])
    render json: categories
  end
  
  # POST /menus/:menu_id/categories
  def create
    result = category_service.create_category(params[:menu_id], category_params)
    
    if result[:success]
      render json: result[:category], status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # PATCH/PUT /menus/:menu_id/categories/:id
  def update
    result = category_service.update_category(params[:menu_id], params[:id], category_params)
    
    if result[:success]
      render json: result[:category]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # DELETE /menus/:menu_id/categories/:id
  def destroy
    result = category_service.delete_category(params[:menu_id], params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  private
  
  def category_params
    params.require(:category).permit(:name, :position, :description)
  end
  
  def category_service
    @category_service ||= begin
      service = CategoryService.new(current_restaurant)
      service.current_user = current_user
      service
    end
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
end
