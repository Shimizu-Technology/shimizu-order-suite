# app/services/settings_service.rb
class SettingsService < TenantScopedService
  # Get settings for the current restaurant
  def get_settings
    {
      restaurant_id:              restaurant.id,
      name:                       restaurant.name,
      default_reservation_length: restaurant.default_reservation_length,
      time_slot_interval:         restaurant.time_slot_interval,
      time_zone:                  restaurant.time_zone,
      # We do not show opening_time or closing_time if removed
      admin_settings:             restaurant.admin_settings
    }
  end

  # Update settings for the current restaurant
  def update_settings(settings_params)
    if restaurant.update(settings_params)
      {
        success: true,
        message: "Settings updated successfully",
        restaurant_id:              restaurant.id,
        default_reservation_length: restaurant.default_reservation_length,
        time_slot_interval:         restaurant.time_slot_interval,
        time_zone:                  restaurant.time_zone,
        admin_settings:             restaurant.admin_settings
      }
    else
      {
        success: false,
        errors: restaurant.errors.full_messages,
        status: :unprocessable_entity
      }
    end
  end
end
