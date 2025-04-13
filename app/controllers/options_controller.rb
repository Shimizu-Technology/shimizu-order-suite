# app/controllers/options_controller.rb
class OptionsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request
  before_action :ensure_tenant_context

  # POST /option_groups/:option_group_id/options
  def create
    result = option_service.create_option(params[:option_group_id], option_params)
    
    if result[:success]
      render json: result[:option].as_json(methods: [ :additional_price_float ]), status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # PATCH /options/:id
  def update
    result = option_service.update_option(params[:id], option_params)
    
    if result[:success]
      render json: result[:option].as_json(methods: [ :additional_price_float ])
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # DELETE /options/:id
  def destroy
    result = option_service.delete_option(params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  private

  def option_params
    # Adjust based on your actual Option columns
    params.require(:option).permit(:name, :additional_price, :available, :is_preselected, :is_available)
  end

  def option_service
    @option_service ||= begin
      service = OptionService.new(current_restaurant)
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
