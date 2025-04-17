# config/initializers/action_cable_config.rb

# This initializer explicitly configures ActionCable allowed request origins
# to ensure WebSocket connections work correctly from all frontend domains

Rails.application.config.after_initialize do
  # Add explicit allowed origins for ActionCable
  allowed_origins = [
    'https://hafaloha.netlify.app',
    'https://hafaloha-lvmt0.kinsta.page',
    'https://hafaloha-orders.com',
    'https://shimizu-order-suite.netlify.app',
    'https://house-of-chin-fe.netlify.app'
  ]
  
  # Add localhost origins for development
  if Rails.env.development?
    allowed_origins += [
      'http://localhost:5173',
      'http://localhost:5174',
      'http://localhost:5175',
      'http://localhost:5176'
    ]
  end
  
  # Get any existing allowed origins
  existing_origins = Rails.application.config.action_cable.allowed_request_origins || []
  
  # Combine and set the allowed request origins
  all_origins = (existing_origins + allowed_origins).uniq
  Rails.application.config.action_cable.allowed_request_origins = all_origins
  
  # Log the configuration for debugging
  Rails.logger.info "ActionCable allowed request origins: #{all_origins.inspect}"
end
