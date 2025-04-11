# app/services/operating_hours_service.rb
class OperatingHoursService < TenantScopedService
  # Get all operating hours for the current restaurant
  def list_hours
    scope_query(OperatingHour).order(:day_of_week)
  end

  # Update an operating hour record
  def update_hour(id, operating_hour_params)
    operating_hour = scope_query(OperatingHour).find(id)
    
    if operating_hour.update(operating_hour_params)
      { success: true, operating_hour: operating_hour }
    else
      { 
        success: false, 
        errors: operating_hour.errors.full_messages, 
        status: :unprocessable_entity 
      }
    end
  rescue ActiveRecord::RecordNotFound
    { 
      success: false, 
      errors: ["Operating hour not found"], 
      status: :not_found 
    }
  end
end
