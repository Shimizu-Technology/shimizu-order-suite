# app/controllers/admin/site_settings_controller.rb
module Admin
  class SiteSettingsController < ApplicationController
    include TenantIsolation
    
    before_action :authorize_request, except: [ :show ]
    before_action :require_admin!, except: [ :show ]
    before_action :ensure_tenant_context

    # GET /admin/site_settings
    def show
      # Use the SiteSettingsService to get settings with tenant isolation
      settings = site_settings_service.get_settings
      render json: settings
    end

    # PATCH /admin/site_settings
    # Accepts optional file fields: hero_image, spinner_image
    def update
      # Use the SiteSettingsService to update settings with tenant isolation
      result = site_settings_service.update_settings(params)
      
      if result[:success]
        render json: result[:settings]
      else
        render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
      end
    end

    private

    def require_admin!
      unless current_user&.role.in?(%w[admin super_admin])
        render json: { error: "Forbidden" }, status: :forbidden
      end
    end
    
    def site_settings_service
      @site_settings_service ||= SiteSettingsService.new(current_restaurant)
    end
    
    def ensure_tenant_context
      unless current_restaurant.present?
        render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
      end
    end
  end
end
