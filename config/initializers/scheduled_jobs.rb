# Scheduled job initializer
# This initializer ensures that recurring jobs are scheduled on application startup
#
# Only schedules jobs when running in a Sidekiq server process or in the Rails server

Rails.application.config.after_initialize do
  # Only schedule if we're in a server environment (not in rake tasks, console, etc.)
  if defined?(Rails::Server) || (defined?(Sidekiq) && Sidekiq.server?)
    Rails.logger.info "Initializing scheduled jobs"
    
    # Schedule the persistent low stock notification job
    if Rails.env.production? || Rails.env.staging?
      # In production/staging, schedule the job to start immediately unless already scheduled
      PersistentLowStockNotificationJob.schedule_job
      Rails.logger.info "PersistentLowStockNotificationJob scheduled in #{Rails.env} environment"
    else
      # In development/test, only log that we would schedule but don't actually do it
      # unless explicitly requested via env var
      if ENV['SCHEDULE_DEV_JOBS'] == 'true'
        PersistentLowStockNotificationJob.schedule_job
        Rails.logger.info "PersistentLowStockNotificationJob scheduled in #{Rails.env} environment"
      else
        Rails.logger.info "PersistentLowStockNotificationJob would be scheduled in production (skipped in #{Rails.env})"
      end
    end
    
    # Add other scheduled jobs here as needed
  end
end
