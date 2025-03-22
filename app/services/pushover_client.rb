# app/services/pushover_client.rb
require 'net/http'
require 'uri'
require 'json'

class PushoverClient
  PUSHOVER_API_URL = "https://api.pushover.net/1".freeze
  DEFAULT_APP_TOKEN = ENV['PUSHOVER_APP_TOKEN'].freeze

  # Send a notification to Pushover
  # @param user_key [String] The user key or group key to send the notification to
  # @param message [String] The message body
  # @param title [String] The notification title (optional)
  # @param priority [Integer] The notification priority (-2 to 2, default 0)
  # @param app_token [String] The app token to use (optional, uses default if not provided)
  # @param sound [String] The sound to play (optional)
  # @param url [String] A URL to include (optional)
  # @param url_title [String] The title for the URL (optional)
  # @return [Boolean] Whether the notification was sent successfully
  def self.send_notification(user_key:, message:, title: nil, priority: 0, 
                            app_token: nil, sound: nil, url: nil, url_title: nil)
    # Use the provided app token or fall back to the default
    token = app_token.presence || DEFAULT_APP_TOKEN
    
    # Return false if no token is available
    return false if token.blank?
    
    # Build the request parameters
    params = {
      token: token,
      user: user_key,
      message: message,
      priority: priority
    }
    
    # Add optional parameters if provided
    params[:title] = title if title.present?
    params[:sound] = sound if sound.present?
    params[:url] = url if url.present?
    params[:url_title] = url_title if url_title.present?
    
    # Add retry and expire parameters for emergency priority
    if priority == 2
      params[:retry] = 60 unless params.key?(:retry)
      params[:expire] = 3600 unless params.key?(:expire)
    end
    
    # Send the request
    uri = URI.parse("#{PUSHOVER_API_URL}/messages.json")
    response = Net::HTTP.post_form(uri, params)
    
    # Parse the response
    begin
      result = JSON.parse(response.body)
      Rails.logger.info("Pushover response: #{result.inspect}")
      
      # Return true if the request was successful
      return result["status"] == 1
    rescue => e
      Rails.logger.error("Error parsing Pushover response: #{e.message}")
      return false
    end
  end
  
  # Validate a user key
  # @param user_key [String] The user key or group key to validate
  # @param app_token [String] The app token to use (optional, uses default if not provided)
  # @return [Boolean] Whether the user key is valid
  def self.validate_user_key(user_key, app_token = nil)
    # Use the provided app token or fall back to the default
    token = app_token.presence || DEFAULT_APP_TOKEN
    
    # Return false if no token is available
    return false if token.blank?
    
    # Build the request parameters
    params = {
      token: token,
      user: user_key
    }
    
    # Send the request
    uri = URI.parse("#{PUSHOVER_API_URL}/users/validate.json")
    response = Net::HTTP.post_form(uri, params)
    
    # Parse the response
    begin
      result = JSON.parse(response.body)
      Rails.logger.info("Pushover validation response: #{result.inspect}")
      
      # Return true if the request was successful
      return result["status"] == 1
    rescue => e
      Rails.logger.error("Error parsing Pushover validation response: #{e.message}")
      return false
    end
  end
end
