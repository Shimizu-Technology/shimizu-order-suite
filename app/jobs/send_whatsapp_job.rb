# app/jobs/send_whatsapp_job.rb
class SendWhatsappJob < ApplicationJob
  queue_as :default

  def perform(group_id, message_text)
    WassengerClient.new.send_group_message(group_id, message_text)
  end
end
