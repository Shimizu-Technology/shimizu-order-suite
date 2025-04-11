# app/controllers/option_groups_controller.rb
class OptionGroupsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request
  before_action :ensure_tenant_context

  # GET /menu_items/:menu_item_id/option_groups
  def index
    option_groups = option_group_service.list_option_groups(params[:menu_item_id])

    render json: option_groups.as_json(
      include: {
        options: {
          methods: [ :additional_price_float ]
        }
      }
    )
  end

  # POST /menu_items/:menu_item_id/option_groups
  def create
    result = option_group_service.create_option_group(params[:menu_item_id], option_group_params)
    
    if result[:success]
      render json: result[:option_group].as_json(
        include: {
          options: {
            methods: [ :additional_price_float ]
          }
        }
      ), status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # PATCH /option_groups/:id
  def update
    result = option_group_service.update_option_group(params[:id], option_group_params)
    
    if result[:success]
      render json: result[:option_group].as_json(
        include: {
          options: {
            methods: [ :additional_price_float ]
          }
        }
      )
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # DELETE /option_groups/:id
  def destroy
    result = option_group_service.delete_option_group(params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  private

  def option_group_params
    # Adjust permitted params based on your actual OptionGroup columns
    params.require(:option_group).permit(:name, :min_select, :max_select, :free_option_count)
  end

  def option_group_service
    @option_group_service ||= begin
      service = OptionGroupService.new(current_restaurant)
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
