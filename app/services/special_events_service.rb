# app/services/special_events_service.rb
class SpecialEventsService < TenantScopedService
  # Get all special events for the current restaurant
  def list_events
    scope_query(SpecialEvent).order(:event_date)
  end

  # Get a specific special event for the current restaurant
  def get_event(id)
    scope_query(SpecialEvent).find(id)
  end

  # Create a new special event for the current restaurant
  def create_event(event_params)
    event = scope_query(SpecialEvent).new(event_params)
    
    if event.save
      { success: true, event: event, status: :created }
    else
      { success: false, errors: event.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Update an existing special event for the current restaurant
  def update_event(id, event_params)
    event = scope_query(SpecialEvent).find(id)
    
    if event.update(event_params)
      { success: true, event: event }
    else
      { success: false, errors: event.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Delete a special event for the current restaurant
  def delete_event(id)
    event = scope_query(SpecialEvent).find(id)
    event.destroy
    { success: true }
  end
end
