# app/mailers/password_mailer.rb
require "cgi"  # for CGI.escape

class PasswordMailer < ApplicationMailer
  def reset_password(user, raw_token)
    @user = user
    @restaurant = get_restaurant_for(@user)
    @header_color = email_header_color_for(@restaurant)

    # URL-encode the email so that '+' stays '%2B', etc.
    safe_email = CGI.escape(@user.email)
    
    # Get the frontend URL for this restaurant using our helper method
    frontend_url = get_frontend_url_for(@restaurant)

    # Build the reset link using safe_email and restaurant-specific frontend URL
    @url = "#{frontend_url}/reset-password?token=#{raw_token}&email=#{safe_email}"

    mail(
      to: @user.email,
      from: restaurant_from_address(@restaurant),
      subject: "Reset your #{@restaurant&.name || 'Restaurant'} password"
    )
  end
end
