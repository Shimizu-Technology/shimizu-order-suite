# app/helpers/mailer_helper.rb
module MailerHelper
  # Helper methods for mailers
  
  # Returns the verified sender email address for SendGrid
  def default_from_address
    'ShimizuTechnology@gmail.com'
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
    # Try different ways to get the color based on restaurant structure
    restaurant&.admin_settings&.dig('email_header_color') || 
    restaurant&.primary_color || 
    '#4A5568' # Default gray if no color is found
  end
end
