# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from: "Rotary Sushi <4lmshimizu@gmail.com>"
  layout "mailer"
end
