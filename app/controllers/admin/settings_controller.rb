# app/controllers/admin/settings_controller.rb
module Admin
  class SettingsController < ApplicationController
    include TenantIsolation
    
    before_action :authorize_request
    before_action :require_admin
    before_action :ensure_tenant_context

    # GET /admin/settings
    def show
      # Use the SettingsService to get settings with tenant isolation
      settings = settings_service.get_settings
      render json: settings
    end

    # PATCH/PUT /admin/settings
    def update
      # Use the SettingsService to update settings with tenant isolation
      result = settings_service.update_settings(settings_params)
      
      if result[:success]
        render json: result
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
    
    def settings_service
      @settings_service ||= SettingsService.new(current_restaurant)
    end
    
    def ensure_tenant_context
      unless current_restaurant.present?
        render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
      end
    end

    def settings_params
      # Removed :opening_time / :closing_time if they're gone from the DB
      params.require(:restaurant).permit(
        :default_reservation_length,
        :time_slot_interval,
        :time_zone,
        admin_settings: {}
      )
    end
  end
end
