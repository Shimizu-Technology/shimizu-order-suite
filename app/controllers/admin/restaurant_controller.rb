# app/controllers/admin/restaurant_controller.rb

module Admin
  class RestaurantController < ApplicationController
    before_action :authorize_request
    before_action :require_admin!

    # Mark all actions as public endpoints that don't require restaurant context
    def public_endpoint?
      true
    end

    # GET /admin/restaurant/allowed_origins
    def allowed_origins
      restaurant = Restaurant.find(params[:restaurant_id] || current_user&.restaurant_id || 1)
      render json: { allowed_origins: restaurant.allowed_origins || [] }
    end

    # POST /admin/restaurant/allowed_origins
    def update_allowed_origins
      restaurant = Restaurant.find(params[:restaurant_id] || current_user&.restaurant_id || 1)

      if params[:allowed_origins].is_a?(Array)
        restaurant.allowed_origins = params[:allowed_origins]
        if restaurant.save
          render json: { allowed_origins: restaurant.allowed_origins }
        else
          render json: { errors: restaurant.errors.full_messages }, status: :unprocessable_entity
        end
      else
        render json: { error: "allowed_origins must be an array" }, status: :unprocessable_entity
      end
    end

    private

    def require_admin!
      unless current_user && current_user.role.in?(%w[admin super_admin])
        render json: { error: "Forbidden" }, status: :forbidden
      end
    end
  end
end
