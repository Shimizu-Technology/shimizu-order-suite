# app/jobs/send_sms_job.rb
class SendSmsJob < ApplicationJob
  queue_as :default

  def perform(to:, body:, from:)
    # The actual call to your SMS client
    ClicksendClient.send_text_message(
      to:   to,
      body: body,
      from: from
    )
  end
end
