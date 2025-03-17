# app/helpers/mailer_helper.rb
module MailerHelper
  # Helper methods for mailers

  # Returns the verified sender email address for SendGrid
  def default_from_address
    "ShimizuTechnology@gmail.com"
  end

  # Returns a formatted from address with the restaurant name
  # Format: "Restaurant Name <verified_email@example.com>"
  def restaurant_from_address(restaurant)
    "#{restaurant.name} <ShimizuTechnology@gmail.com>"
  end

  # Get the restaurant for an order
  def get_restaurant_for(order)
    order.restaurant
  end

  # Get the email header color for a restaurant
  def email_header_color_for(restaurant)
    # Get color from admin_settings or use default
    restaurant&.admin_settings&.dig("email_header_color") || "#D4AF37" # Default Hafaloha gold if no color is found
  end
end
