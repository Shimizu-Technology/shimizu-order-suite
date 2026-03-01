# app/mailers/concerns/mailer_helper.rb
module MailerHelper
  def mailer_from_email
    ENV.fetch("RESEND_FROM_EMAIL", "noreply@shimizu-technology.com")
  end

  # Get the email header color for a given restaurant
  # Falls back to a default gold color if not set
  def email_header_color_for(restaurant)
    return "#c1902f" unless restaurant

    # Get the color from the restaurant's admin_settings, or use the default
    restaurant.admin_settings&.dig("email_header_color") || "#c1902f"
  end

  # Get the from address for a given restaurant
  # Uses the restaurant's email domain if configured, or falls back to defaults
  # Always uses the restaurant name as the display name
  def from_address_for(restaurant)
    return default_from_address unless restaurant

    # Always use the restaurant name as the display name
    email_name = restaurant.name

    # Ensure the name is properly formatted for email headers
    formatted_name = email_name.gsub('"', '\\"')

    # Get the appropriate email address for this restaurant
    email = email_for_restaurant(restaurant)

    # Format with display name
    "#{formatted_name} <#{email}>"
  end

  def default_from_email
    mailer_from_email
  end

  # Get the default from address (name + email)
  def default_from_address
    # Try to get the first restaurant's name as the default
    first_restaurant = Restaurant.first
    default_name = if first_restaurant
                     first_restaurant.name
    else
                     "ShimizuTechnology"
    end

    # If we have a first restaurant, use its email domain
    if first_restaurant
      "#{default_name} <#{email_for_restaurant(first_restaurant)}>"
    else
      "#{default_name} <#{mailer_from_email}>"
    end
  end

  # Get the restaurant for a given record
  # This handles different types of records that might be associated with a restaurant
  def get_restaurant_for(record)
    return nil unless record

    if record.is_a?(Restaurant)
      record
    elsif record.respond_to?(:restaurant)
      record.restaurant
    elsif record.respond_to?(:restaurant_id)
      Restaurant.find_by(id: record.restaurant_id)
    else
      nil
    end
  end
  
  # Get the from address for a given restaurant
  # This is the method called by all mailers
  def restaurant_from_address(restaurant)
    from_address_for(restaurant)
  end
  
  # Determine the sender email for a restaurant.
  # For deliverability providers like Resend, keep sender domain fixed
  # to a verified domain instead of dynamically deriving from contact_email.
  def email_for_restaurant(restaurant)
    return default_fallback_email unless restaurant
    mailer_from_email
  end
  
  def default_fallback_email
    mailer_from_email
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
