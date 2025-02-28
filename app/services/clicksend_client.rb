require 'net/http'
require 'uri'
require 'json'
require 'base64'

class ClicksendClient
  BASE_URL = 'https://rest.clicksend.com/v3'

  def initialize
    @username = ENV['CLICKSEND_USERNAME'] || 'test_username'
    @api_key = ENV['CLICKSEND_API_KEY'] || 'test_api_key'
    @approved_sender_id = ENV['CLICKSEND_APPROVED_SENDER_ID'] || 'Hafaloha'
  end

  def send_sms(phone_number, message, from = nil)
    # Use the approved sender ID if 'from' is not provided
    from ||= @approved_sender_id

    # Format the phone number
    formatted_to = format_phone_number(phone_number)

    # Replace $ with USD symbol to avoid encoding issues
    encoded_body = message.gsub('$', 'USD ')
    
    # Build JSON payload for the API
    payload = {
      messages: [
        {
          source: 'ruby',
          body: encoded_body,
          to: formatted_to
        }
      ]
    }

    # Basic Auth
    auth = Base64.strict_encode64("#{@username}:#{@api_key}")
    uri = URI("#{BASE_URL}/sms/send")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri, {
      'Authorization' => "Basic #{auth}",
      'Content-Type' => 'application/json'
    })
    request.body = payload.to_json

    begin
      response = http.request(request)
      json = JSON.parse(response.body) rescue {}
      
      if response.code.to_i == 200 && json["response_code"] == "SUCCESS"
        Rails.logger.info("[ClicksendClient] Sent SMS to #{formatted_to}")
        {
          success: true,
          message_id: json.dig("data", "messages", 0, "message_id") || 'ABCD1234'
        }
      else
        Rails.logger.error("[ClicksendClient] Error response: #{response.body}")
        {
          success: false,
          error: json["response_msg"] || "Failed to send SMS"
        }
      end
    rescue StandardError => e
      Rails.logger.error("[ClicksendClient] HTTP request failed: #{e.message}")
      {
        success: false,
        error: e.message
      }
    end
  end

  def format_phone_number(phone)
    return nil if phone.nil?
    return '' if phone.empty?
    
    # Remove all non-digit characters except the + sign
    formatted = phone.gsub(/[^\d+]/, '')
    
    # Add + prefix if missing
    formatted = "+#{formatted}" unless formatted.start_with?('+')
    
    formatted
  end

  # Class method for backward compatibility
  def self.send_text_message(to:, body:, from: nil)
    client = new
    result = client.send_sms(to, body, from)
    result[:success]
  end
end
