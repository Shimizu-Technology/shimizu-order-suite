# Scheduled job initializer
# This initializer ensures that recurring jobs are scheduled on application startup
#
# Only schedules jobs when running in a Sidekiq server process or in the Rails server

Rails.application.config.after_initialize do
  # Only schedule if we're in a server environment (not in rake tasks, console, etc.)
  if defined?(Rails::Server) || (defined?(Sidekiq) && Sidekiq.server?)
    Rails.logger.info "Initializing scheduled jobs"

    # Scheduled jobs will be added here as needed
    Rails.logger.info "No scheduled jobs to initialize"

    # Add other scheduled jobs here as needed
  end
end
