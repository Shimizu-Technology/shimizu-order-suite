require 'rufus-scheduler'

# Only run scheduler in production and staging environments to avoid
# running jobs in development or test environments
if defined?(Rails) && (Rails.env.production? || Rails.env.staging?)
  scheduler = Rufus::Scheduler.singleton
  
  # Schedule jobs
  
  # Send reservation reminders daily at 12:00 PM
  # This job will find all reservations happening in the next 24-25 hours
  # and send reminder emails and/or SMS
  scheduler.cron '0 12 * * *' do
    Rails.logger.info "Running ReservationReminderJob"
    ReservationReminderJob.perform_later
  end
  
  # Additional scheduler jobs can be added here
end
