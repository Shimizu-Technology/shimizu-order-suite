# config/initializers/sms_client.rb
Rails.configuration.after_initialize do
  # Check if ClickSend credentials are configured
  if Rails.env.production? || Rails.env.staging?
    required_vars = %w[CLICKSEND_USERNAME CLICKSEND_API_KEY]
    missing_vars = required_vars.select { |var| ENV[var].blank? }
    
    if missing_vars.any?
      Rails.logger.error "SMS SERVICE NOT FULLY CONFIGURED: Missing required environment variables: #{missing_vars.join(', ')}"
    else
      Rails.logger.info "SMS service configured with credentials for: #{ENV['CLICKSEND_USERNAME']}"
    end
  end
end
