class WebhookDeliveryJob < ApplicationJob
  queue_as :webhooks
  
  def perform(endpoint_id, event_type, payload)
    endpoint = WebhookEndpoint.find_by(id: endpoint_id)
    return unless endpoint&.active?
    
    # Prepare the payload
    webhook_payload = {
      event_type: event_type,
      restaurant_id: endpoint.restaurant_id,
      timestamp: Time.current.iso8601,
      data: payload
    }
    
    payload_json = webhook_payload.to_json
    signature = OpenSSL::HMAC.hexdigest('SHA256', endpoint.secret, payload_json)
    
    # Make the HTTP request
    begin
      response = Faraday.post(endpoint.url) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.headers['X-Hafaloha-Signature'] = signature
        req.headers['X-Hafaloha-Event'] = event_type
        req.body = payload_json
      end
      
      # Log the result
      if response.success?
        Rails.logger.info("[Webhook] Successfully delivered #{event_type} to #{endpoint.url}")
      else
        Rails.logger.error("[Webhook] Failed to deliver #{event_type} to #{endpoint.url}: #{response.status} #{response.body}")
      end
    rescue => e
      Rails.logger.error("[Webhook] Error delivering webhook to #{endpoint.url}: #{e.message}")
      retry_job(wait: 30.seconds) if executions < 3
    end
  end
end
