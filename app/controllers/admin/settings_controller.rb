# app/controllers/admin/settings_controller.rb
module Admin
  class SettingsController < ApplicationController
    before_action :authorize_request
    before_action :require_admin

    # GET /admin/settings
    # Return the current restaurant's admin settings (or load by param if multi-tenant).
    def show
      restaurant = current_user.restaurant
      render json: {
        restaurant_id:              restaurant.id,
        name:                       restaurant.name,
        default_reservation_length: restaurant.default_reservation_length,
        opening_time:               restaurant.opening_time,
        closing_time:               restaurant.closing_time,
        time_slot_interval:         restaurant.time_slot_interval,
        admin_settings:             restaurant.admin_settings
      }
    end

    # PATCH/PUT /admin/settings
    # Update these settings in the restaurants table
    def update
      restaurant = current_user.restaurant
      if restaurant.update(settings_params)
        render json: {
          message:                    "Settings updated successfully",
          restaurant_id:              restaurant.id,
          default_reservation_length: restaurant.default_reservation_length,
          opening_time:               restaurant.opening_time,
          closing_time:               restaurant.closing_time,
          time_slot_interval:         restaurant.time_slot_interval,
          admin_settings:             restaurant.admin_settings
        }
      else
        render json: { errors: restaurant.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def require_admin
      # Example check: allow role = 'admin' or 'super_admin'
      unless current_user.role.in?(%w[admin super_admin])
        render json: { error: "Forbidden: admin only" }, status: :forbidden
      end
    end

    def settings_params
      # Permit the fields you want to allow from your admin UI
      params.require(:restaurant).permit(
        :default_reservation_length,
        :opening_time,
        :closing_time,
        :time_slot_interval,
        admin_settings: {}
      )
    end
  end
end
