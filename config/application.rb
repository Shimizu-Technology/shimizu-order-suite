# config/application.rb

require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module ShimizuOrderSuite
  class Application < Rails::Application
    config.load_defaults 7.2

    # This ensures that Time.zone = 'Pacific/Guam' throughout your app:
    config.time_zone = "Pacific/Guam"

    # Store DB times in UTC:
    config.active_record.default_timezone = :utc

    # Autoload lib/ except certain subdirectories
    config.autoload_lib(ignore: %w[assets tasks])

    # API-only mode
    config.api_only = true

    # Use Sidekiq for background jobs
    config.active_job.queue_adapter = :sidekiq
    
    # Preload TenantContext concern for multi-tenant support
    config.to_prepare do
      require_dependency Rails.root.join('app', 'models', 'concerns', 'tenant_context.rb')
    end
    
    # Add TenantValidationMiddleware for multi-tenant security
    config.middleware.use TenantValidationMiddleware, {
      rate_limit_window: ENV.fetch("TENANT_RATE_LIMIT_WINDOW", 60).to_i,
      rate_limit_max_requests: ENV.fetch("TENANT_RATE_LIMIT_MAX_REQUESTS", 100).to_i
    } if defined?(TenantValidationMiddleware)
    
    # Add TenantMetricsMiddleware for tenant analytics and monitoring
    config.middleware.use TenantMetricsMiddleware if defined?(TenantMetricsMiddleware)
  end
end
