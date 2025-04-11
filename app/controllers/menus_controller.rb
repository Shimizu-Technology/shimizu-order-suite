# app/controllers/menus_controller.rb
class MenusController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request, except: [:index, :show]
  before_action :optional_authorize, only: [:index, :show]
  before_action :ensure_tenant_context

  # GET /menus
  def index
    menus = menu_service.list_menus(params)
    render json: menus
  end

  # GET /menus/1
  def show
    menu = menu_service.find_menu(params[:id])
    render json: menu
  end

  # POST /menus
  def create
    result = menu_service.create_menu(menu_params)
    
    if result[:success]
      render json: result[:menu], status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # PATCH/PUT /menus/1
  def update
    result = menu_service.update_menu(params[:id], menu_params)
    
    if result[:success]
      render json: result[:menu]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # DELETE /menus/1
  def destroy
    result = menu_service.delete_menu(params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /menus/:id/set_active
  def set_active
    result = menu_service.set_active_menu(params[:id])
    
    if result[:success]
      render json: {
        message: result[:message],
        current_menu_id: result[:current_menu_id]
      }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /menus/:id/clone
  def clone
    result = menu_service.clone_menu(params[:id])
    
    if result[:success]
      render json: result[:menu], status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  private

  def menu_params
    params.require(:menu).permit(:name, :active)
  end

  def menu_service
    @menu_service ||= begin
      service = MenuService.new(current_restaurant)
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
