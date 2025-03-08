# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  include MailerHelper
  
  # Use a verified sender identity for SendGrid
  default from: 'ShimizuTechnology@gmail.com'
  
  layout "mailer"
  
  private
  
  def default_from_address
    'ShimizuTechnology@gmail.com'
  end
end
