# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  include MailerHelper

  # Use a verified sender identity for SendGrid
  default from: -> { default_from_email }

  layout "mailer"

end
