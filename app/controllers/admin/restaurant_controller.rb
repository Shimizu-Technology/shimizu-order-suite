# app/controllers/admin/restaurant_controller.rb

module Admin
  class RestaurantController < ApplicationController
    include TenantIsolation
    
    before_action :authorize_request
    before_action :require_admin!
    # Skip ensure_tenant_context for index action since it's a global operation
    before_action :ensure_tenant_context, except: [:index]

    # GET /admin/restaurants
    def index
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
      # For global operations like index, don't pass a restaurant
      if action_name == "index" && current_user&.super_admin?
        @restaurant_management_service ||= RestaurantManagementService.new(nil, current_user)
      else
        @restaurant_management_service ||= RestaurantManagementService.new(current_restaurant, current_user)
      end
    end
    
    # Override global_access_permitted to allow super_admin to access global endpoints
    def global_access_permitted?
      current_user&.super_admin? && action_name.in?(["index"])
    end
    
    def ensure_tenant_context
      unless current_restaurant.present?
        render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
      end
    end
  end
end
