# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  include MailerHelper

  # Use a verified sender identity for SendGrid
  default from: -> { default_from_email }

  layout "mailer"

  # Add logging to track email delivery timing
  after_action :log_email_queuing

  private

  def log_email_queuing
    recipient = mail.to&.first || 'unknown'
    subject = mail.subject || 'no subject'
    
    Rails.logger.info("[EMAIL QUEUE] #{self.class.name} queued for #{recipient} - Subject: #{subject} - Time: #{Time.current}")
    
    # Safely check queue sizes if Sidekiq is available
    begin
      require 'sidekiq/api'
      default_size = Sidekiq::Queue.new('default').size
      mailers_size = Sidekiq::Queue.new('mailers').size
      sms_size = Sidekiq::Queue.new('sms').size
      Rails.logger.info("[QUEUE SIZES] default: #{default_size}, mailers: #{mailers_size}, sms: #{sms_size}")
    rescue => e
      Rails.logger.info("[EMAIL QUEUE] Could not check queue sizes: #{e.message}")
    end
  end
end
