class WebhookService
  class << self
    def trigger(event_type, payload, restaurant_id)
      # Skip if no payload or restaurant_id
      return if payload.blank? || restaurant_id.blank?
      
      # Find all active endpoints for this restaurant that listen for this event
      endpoints = WebhookEndpoint.where(
        restaurant_id: restaurant_id,
        active: true
      ).where("? = ANY(event_types)", event_type)
      
      # Process each endpoint in a background job
      endpoints.each do |endpoint|
        WebhookDeliveryJob.perform_later(endpoint.id, event_type, payload)
      end
      
      # Also broadcast to WebSocket for browser clients
      ActionCable.server.broadcast(
        "restaurant_events_#{restaurant_id}",
        {
          type: event_type,
          data: payload
        }
      )
      
      # Return success
      true
    end
  end
end
