# config/initializers/action_cable.rb
#
# Configure ActionCable to allow WebSocket connections from our frontend domains

Rails.application.config.action_cable.allowed_request_origins = [
  # Local development
  'http://localhost:5173',
  'http://localhost:5174',
  'http://localhost:5175',
  
  # Production domains
  'https://hafaloha-orders.com',
  'https://hafaloha.netlify.app',
  'https://hafaloha-lvmt0.kinsta.page',
  'https://shimizu-order-suite.netlify.app'
]

# Log allowed origins on startup
Rails.application.config.after_initialize do
  Rails.logger.info "ActionCable allowed origins: #{Rails.application.config.action_cable.allowed_request_origins.inspect}"
end
