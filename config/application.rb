# config/application.rb

require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module RotaryReservationsApi
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

    # ADD THIS => use Sidekiq for background jobs
    config.active_job.queue_adapter = :sidekiq
  end
end
