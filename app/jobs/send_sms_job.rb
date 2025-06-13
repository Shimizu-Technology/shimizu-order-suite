# app/jobs/send_sms_job.rb
class SendSmsJob < ApplicationJob
  queue_as :sms
  
  # SMS is important for customer communication, but can expire after 6 hours
  sidekiq_options retry: 5, expires_in: 6.hours

  def perform(to:, body:, from:)
    start_time = Time.current
    Rails.logger.info("[SMS QUEUE] Processing SMS to #{to} from #{from} - Started: #{start_time}")
    
    # The actual call to your SMS client
    result = ClicksendClient.send_text_message(
      to:   to,
      body: body,
      from: from
    )
    
    end_time = Time.current
    duration = ((end_time - start_time) * 1000).round(2) # milliseconds
    Rails.logger.info("[SMS QUEUE] SMS to #{to} completed in #{duration}ms - Success: #{result}")
    
    result
  end
end
