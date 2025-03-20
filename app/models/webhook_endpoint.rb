class WebhookEndpoint < ApplicationRecord
  belongs_to :restaurant
  validates :url, presence: true
  validates :secret, presence: true
  
  # Define common event types
  EVENT_TYPES = [
    'order.created',
    'order.updated',
    'order.status_changed',
    'inventory.low_stock',
    'reservation.created',
    'reservation.updated'
  ]
  
  # Verify the HMAC signature from a webhook request
  def verify_signature(payload, signature)
    calculated = OpenSSL::HMAC.hexdigest('SHA256', secret, payload)
    ActiveSupport::SecurityUtils.secure_compare(calculated, signature)
  end
end
