# config/environments/production.rb

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # --------------------------------
  # Core Rails & caching (unchanged)
  # --------------------------------
  config.enable_reloading            = false
  config.eager_load                  = true
  config.consider_all_requests_local = false
  config.active_storage.service      = :amazon
  config.force_ssl                   = true

  config.logger = ActiveSupport::TaggedLogging.new(
    ActiveSupport::Logger.new($stdout).tap { _1.formatter = ::Logger::Formatter.new }
  )
  config.log_tags  = [:request_id]
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  if ENV["REDIS_URL"]
    config.cache_store = :redis_cache_store, { url: ENV["REDIS_URL"] }
  else
    config.cache_store = :memory_store, { size: 64.megabytes }
  end

  config.action_controller.perform_caching = true
  config.public_file_server.headers = { "Cache-Control" => "public, max-age=31536000" }

  # --------------------------------
  # Action Mailer → SendGrid
  # --------------------------------
  mail_domain = ENV.fetch("EMAIL_DOMAIN", "shimizu-order-suite.com")

  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    user_name:            "apikey",
    password:             ENV["SENDGRID_API_KEY"],
    domain:               mail_domain,                   # <— key change
    address:              "smtp.sendgrid.net",
    port:                 587,
    authentication:       :plain,
    enable_starttls_auto: true
  }

  config.action_mailer.default_url_options = { host: mail_domain, protocol: "https" }

  # (Optional) force every mailer to use the shared From address;
  # comment this out if you prefer ApplicationMailer’s helper logic.
  # config.action_mailer.default_options = { from: "orders@#{mail_domain}" }

  config.action_mailer.perform_caching = false

  # --------------------------------
  # I18n, Active Record, etc. (unchanged)
  # --------------------------------
  config.i18n.fallbacks                 = true
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Additional DNS rebind etc…
  # config.hosts = [...]
  
  # Action Cable configuration for production
  # Allow WebSocket connections from all restaurant frontend URLs
  
  # Start with the default frontend URL from the environment variable
  allowed_origins = []
  if ENV['FRONTEND_URL']
    allowed_origins << ENV['FRONTEND_URL']
    
    # Parse the URL to extract protocol, host and port
    frontend_uri = URI.parse(ENV['FRONTEND_URL'])
    frontend_host = frontend_uri.host
    frontend_protocol = frontend_uri.scheme
    
    # Also allow subdomains of the default frontend host
    allowed_origins << /#{frontend_protocol}:\/\/.*\.#{Regexp.escape(frontend_host)}/
  end
  
  # Add all restaurant primary_frontend_urls and allowed_origins
  begin
    if defined?(Restaurant) && Restaurant.table_exists?
      # Add primary_frontend_urls from all restaurants
      Restaurant.where.not(primary_frontend_url: [nil, '']).pluck(:primary_frontend_url).each do |url|
        allowed_origins << url unless url.include?('localhost')
      end
      
      # Add allowed_origins from all restaurants
      Restaurant.all.each do |restaurant|
        if restaurant.allowed_origins.present?
          restaurant.allowed_origins.each do |url|
            allowed_origins << url unless url.include?('localhost')
          end
        end
      end
    end
  rescue => e
    # Log error but continue if database isn't available during initialization
    Rails.logger.error("Error loading restaurant frontend URLs for Action Cable: #{e.message}")
  end
  
  # Set the allowed request origins for Action Cable
  config.action_cable.allowed_request_origins = allowed_origins.uniq if allowed_origins.any?
  
  # Use secure WebSockets in production
  # Determine the host URL for Action Cable
  host_url = ENV['HOST_URL'] || (ENV['HEROKU_APP_NAME'] ? "#{ENV['HEROKU_APP_NAME']}.herokuapp.com" : 'localhost:3000')
  config.action_cable.url = "wss://#{host_url}/cable"
  
  # Enable Action Cable in production
  config.action_cable.mount_path = '/cable'
end
