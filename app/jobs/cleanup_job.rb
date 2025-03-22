# app/jobs/cleanup_job.rb
class CleanupJob < ApplicationJob
  queue_as :maintenance
  
  # Run once per day, retry if fails
  sidekiq_options retry: 3
  
  def perform
    # Remove stale push subscriptions older than 30 days
    cleaned_count = PushSubscription.where(active: false)
                    .where('updated_at < ?', 30.days.ago)
                    .delete_all
    
    Rails.logger.info "Cleaned up #{cleaned_count} stale push subscriptions"
    
    # Clean up old Sidekiq job data to prevent Redis bloat
    # This is handled by Sidekiq's own cleanup process with the settings in sidekiq.yml
    
    # Add any other cleanup tasks as needed
    # For example, you might want to archive old orders or clean up temporary data
  end
end
