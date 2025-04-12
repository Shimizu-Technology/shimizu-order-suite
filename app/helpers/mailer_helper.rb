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
    restaurant&.admin_settings&.dig("email_header_color") || "#D4AF37" # Default gold color if no color is found
  end
  
  # Get the frontend URL for a restaurant
  # Uses the restaurant's primary_frontend_url, then allowed_origins, then falls back to the environment variable
  def get_frontend_url_for(restaurant)
    if restaurant&.primary_frontend_url.present?
      # Use the primary frontend URL if it exists
      frontend_url = restaurant.primary_frontend_url
    elsif restaurant&.allowed_origins.present?
      # Fall back to allowed_origins if primary_frontend_url is not set
      # Use the first allowed origin that's not localhost
      production_origins = restaurant.allowed_origins.reject { |origin| origin.include?('localhost') }
      frontend_url = production_origins.first || restaurant.allowed_origins.first
    else
      # Last resort: use the environment variable
      frontend_url = ENV['FRONTEND_URL']
    end
    
    # Log the frontend URL being used for debugging
    Rails.logger.info("Using frontend URL: #{frontend_url} (Restaurant: #{restaurant&.name || 'Unknown'})")
    
    frontend_url
  end
end
