# app/controllers/admin/operating_hours_controller.rb

module Admin
  class OperatingHoursController < ApplicationController
    include TenantIsolation
    
    before_action :authorize_request
    before_action :require_admin
    before_action :ensure_tenant_context

    # GET /admin/operating_hours
    # => lists all OperatingHour records for the current_user’s restaurant
    def index
      operating_hours = operating_hours_service.list_hours
      render json: operating_hours
    end

    # PATCH/PUT /admin/operating_hours/:id => update a single day-of-week row with tenant isolation
    def update
      result = operating_hours_service.update_hour(params[:id], oh_params)
      
      if result[:success]
        render json: result[:operating_hour]
      else
        render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
      end
    end

    private

    def require_admin
      unless current_user.role.in?(%w[admin super_admin])
        render json: { error: "Forbidden: admin only" }, status: :forbidden
      end
    end

    def oh_params
      # Permit the fields we allow staff to change
      params.require(:operating_hour).permit(:day_of_week, :open_time, :close_time, :closed)
    end
    
    def operating_hours_service
      @operating_hours_service ||= OperatingHoursService.new(current_restaurant)
    end
    
    def ensure_tenant_context
      unless current_restaurant.present?
        render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
      end
    end
  end
end
