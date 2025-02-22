# app/mailers/password_mailer.rb
require 'cgi'  # for CGI.escape

class PasswordMailer < ApplicationMailer
  default from: 'Hafaloha <4lmshimizu@gmail.com>'

  def reset_password(user, raw_token)
    @user = user

    # URL-encode the email so that '+' stays '%2B', etc.
    safe_email = CGI.escape(@user.email)

    # Build the reset link using safe_email
    @url = "#{ENV['FRONTEND_URL']}/reset-password?token=#{raw_token}&email=#{safe_email}"

    mail(to: @user.email, subject: "Reset your Hafaloha password")
  end
end
