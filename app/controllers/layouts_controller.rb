# app/controllers/layouts_controller.rb
class LayoutsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request
  before_action :ensure_tenant_context

  # GET /layouts
  def index
    result = layout_service.list_layouts
    
    if result[:success]
      render json: result[:layouts]
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :internal_server_error
    end
  end

  # GET /layouts/:id
  def show
    result = layout_service.find_layout(params[:id])
    
    if result[:success]
      render json: result[:layout]
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :not_found
    end
  end

  # POST /layouts
  def create
    result = layout_service.create_layout(layout_params)
    
    if result[:success]
      render json: result[:layout], status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # PATCH/PUT /layouts/:id
  def update
    result = layout_service.update_layout(params[:id], layout_params)
    
    if result[:success]
      render json: result[:layout]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # DELETE /layouts/:id
  def destroy
    result = layout_service.delete_layout(params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /layouts/:id/activate
  def activate
    result = layout_service.activate_layout(params[:id])
    
    if result[:success]
      render json: { message: result[:message] }, status: :ok
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :unprocessable_entity
    end
  end

  private

  def layout_service
    @layout_service ||= begin
      service = LayoutService.new(current_restaurant)
      service.current_user = current_user
      service
    end
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end

  def layout_params
    params.require(:layout).permit(:name, :restaurant_id, sections_data: {})
  end
end
