# app/mailers/concerns/mailer_helper.rb
module MailerHelper
  # Get the from address for a given restaurant
  # Always use the verified email address from environment variables
  # And always use the restaurant name as the display name
  def from_address_for(restaurant)
    return default_from_address unless restaurant

    # Always use the restaurant name as the display name
    email_name = restaurant.name
    
    # Ensure the name is properly formatted for email headers
    formatted_name = email_name.gsub('"', '\\"')
    
    # Always use the verified email address from environment variables
    "#{formatted_name} <#{default_from_email}>"
  end

  # Get the default from email address from environment variables
  # or fall back to a hardcoded value
  def default_from_email
    'shimizutechnology@gmail.com'
  end

  # Get the default from address (name + email)
  def default_from_address
    # Try to get the first restaurant's name as the default
    first_restaurant = Restaurant.first
    default_name = if first_restaurant
                     first_restaurant.name
                   else
                     'ShimizuTechnology'
                   end
    
    "#{default_name} <#{default_from_email}>"
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
end
