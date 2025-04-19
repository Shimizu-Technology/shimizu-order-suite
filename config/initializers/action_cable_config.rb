# config/initializers/action_cable_config.rb

# This initializer explicitly configures ActionCable allowed request origins
# to ensure WebSocket connections work correctly from all frontend domains

# Define explicit allowed origins for ActionCable
# This needs to run as early as possible in the initialization process
allowed_origins = [
  'https://hafaloha.netlify.app',
  'https://hafaloha-lvmt0.kinsta.page',
  'https://hafaloha-orders.com',
  'https://shimizu-order-suite.netlify.app',
  'https://house-of-chin-fe.netlify.app',
  'https://crab-daddy.netlify.app'
]

# Also add origins with trailing slashes to handle both formats
trailing_slash_origins = allowed_origins.map { |origin| origin + '/' }
allowed_origins = allowed_origins + trailing_slash_origins

# Add localhost origins for development
if Rails.env.development?
  allowed_origins += [
    'http://localhost:5173',
    'http://localhost:5174',
    'http://localhost:5175',
    'http://localhost:5176'
  ]
end

# Directly set the allowed origins on the ActionCable config
# This ensures it's set before ActionCable is initialized
Rails.application.config.action_cable.allowed_request_origins ||= []
Rails.application.config.action_cable.allowed_request_origins += allowed_origins
Rails.application.config.action_cable.allowed_request_origins.uniq!

# Also enable same origin as host to be extra safe
Rails.application.config.action_cable.allow_same_origin_as_host = true

# Also run after initialization to ensure the settings are applied and logged
Rails.application.config.after_initialize do
  # Log the configuration for debugging
  Rails.logger.info "ActionCable allowed request origins: #{Rails.application.config.action_cable.allowed_request_origins.inspect}"
end
