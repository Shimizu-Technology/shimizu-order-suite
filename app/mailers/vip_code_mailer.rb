class VipCodeMailer < ApplicationMailer
  # Use a verified sender identity for SendGrid with dynamic restaurant name
  # The from address is set in each method to include the restaurant name

  def vip_code_notification(email, vip_code, restaurant)
    @vip_code = vip_code
    @restaurant = restaurant
    @header_color = email_header_color_for(restaurant)
    @frontend_url = get_frontend_url_for(restaurant)

    mail(
      from: restaurant_from_address(restaurant),
      to: email,
      subject: "Your VIP Access Code for #{restaurant.name}"
    )
  end
end
