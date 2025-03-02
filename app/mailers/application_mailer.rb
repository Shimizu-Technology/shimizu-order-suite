# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  include MailerHelper
  
  # Default from address will be overridden in individual mailers
  # based on the restaurant associated with the record
  default from: -> { default_from_address }
  
  layout "mailer"
end
