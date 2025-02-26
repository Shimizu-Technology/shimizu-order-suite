# app/controllers/admin/settings_controller.rb
module Admin
  class SettingsController < ApplicationController
    before_action :authorize_request
    before_action :require_admin
    
    # Mark all actions as public endpoints that don't require restaurant context
    def public_endpoint?
      true
    end

    # GET /admin/settings
    def show
      restaurant = current_user.restaurant
      render json: {
        restaurant_id:              restaurant.id,
        name:                       restaurant.name,
        default_reservation_length: restaurant.default_reservation_length,
        time_slot_interval:         restaurant.time_slot_interval,
        time_zone:                  restaurant.time_zone,
        # We do not show opening_time or closing_time if removed
        admin_settings:             restaurant.admin_settings
      }
    end

    # PATCH/PUT /admin/settings
    def update
      restaurant = current_user.restaurant
      if restaurant.update(settings_params)
        render json: {
          message:                    "Settings updated successfully",
          restaurant_id:              restaurant.id,
          default_reservation_length: restaurant.default_reservation_length,
          time_slot_interval:         restaurant.time_slot_interval,
          time_zone:                  restaurant.time_zone,
          admin_settings:             restaurant.admin_settings
        }
      else
        render json: { errors: restaurant.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def require_admin
      unless current_user.role.in?(%w[admin super_admin])
        render json: { error: "Forbidden: admin only" }, status: :forbidden
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
