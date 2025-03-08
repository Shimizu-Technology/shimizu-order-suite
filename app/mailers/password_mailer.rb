# app/mailers/password_mailer.rb
require 'cgi'  # for CGI.escape

class PasswordMailer < ApplicationMailer
  def reset_password(user, raw_token)
    @user = user
    @restaurant = get_restaurant_for(@user)
    @header_color = email_header_color_for(@restaurant)

    # URL-encode the email so that '+' stays '%2B', etc.
    safe_email = CGI.escape(@user.email)

    # Build the reset link using safe_email
    @url = "#{ENV['FRONTEND_URL']}/reset-password?token=#{raw_token}&email=#{safe_email}"

    mail(
      to: @user.email, 
      from: restaurant_from_address(@restaurant),
      subject: "Reset your #{@restaurant&.name || 'Restaurant'} password"
    )
  end
end
