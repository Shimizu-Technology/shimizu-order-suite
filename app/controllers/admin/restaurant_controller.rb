# app/controllers/admin/restaurant_controller.rb

module Admin
  class RestaurantController < ApplicationController
    include TenantIsolation
    
    before_action :authorize_request
    before_action :require_admin!
    before_action :ensure_tenant_context

    # GET /admin/restaurants
    def index
      # Set current_user for the service
      restaurant_management_service.current_user = current_user
      
      # Use the RestaurantManagementService to get restaurants with tenant isolation
      restaurants = restaurant_management_service.list_restaurants
      render json: restaurants
    end

    # GET /admin/restaurant/allowed_origins
    def allowed_origins
      # Use the RestaurantManagementService to get allowed origins with tenant isolation
      result = restaurant_management_service.get_allowed_origins
      render json: result
    end

    # POST /admin/restaurant/allowed_origins
    def update_allowed_origins
      # Use the RestaurantManagementService to update allowed origins with tenant isolation
      result = restaurant_management_service.update_allowed_origins(params[:allowed_origins])
      
      if result[:success]
        render json: { allowed_origins: result[:allowed_origins] }
      else
        render json: { errors: result[:errors] || result[:error] }, status: result[:status] || :unprocessable_entity
      end
    end

    private

    def require_admin!
      unless current_user && current_user.role.in?(%w[admin super_admin])
        render json: { error: "Forbidden" }, status: :forbidden
      end
    end
    
    def restaurant_management_service
      @restaurant_management_service ||= RestaurantManagementService.new(current_restaurant)
    end
    
    def ensure_tenant_context
      unless current_restaurant.present?
        render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
      end
    end
  end
end
