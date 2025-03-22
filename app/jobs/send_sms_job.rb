# app/jobs/send_sms_job.rb
class SendSmsJob < ApplicationJob
  queue_as :sms
  
  # SMS is important for customer communication, but can expire after 6 hours
  sidekiq_options retry: 5, expires_in: 6.hours

  def perform(to:, body:, from:)
    # The actual call to your SMS client
    ClicksendClient.send_text_message(
      to:   to,
      body: body,
      from: from
    )
  end
end
