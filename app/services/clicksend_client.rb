require 'net/http'
require 'uri'
require 'json'
require 'base64'

class ClicksendClient
  BASE_URL = 'https://rest.clicksend.com/v3'

  def self.send_text_message(to:, body:, from: nil)
    username = ENV['CLICKSEND_USERNAME']
    api_key  = ENV['CLICKSEND_API_KEY']
    approved_sender_id = ENV['CLICKSEND_APPROVED_SENDER_ID']

    if username.blank? || api_key.blank?
      Rails.logger.error("[ClicksendClient] Missing ClickSend credentials.")
      return false
    end

    # Use the approved sender ID if 'from' is not provided
    from ||= approved_sender_id

    # Ensure the 'from' field is not too long (ClickSend has an 11 character limit)
    if from.length > 11
      Rails.logger.warn("[ClicksendClient] 'from' field too long (#{from.length} chars), truncating to 11 chars")
      from = from[0...11]
    end

    # Basic Auth
    auth = Base64.strict_encode64("#{username}:#{api_key}")
    uri  = URI("#{BASE_URL}/sms/send")

    # Replace $ with USD symbol to avoid encoding issues
    encoded_body = body.gsub('$', 'USD ')
    
    # Ensure phone number is in E.164 format (e.g., +16714830219)
    formatted_to = to.strip
    unless formatted_to.start_with?('+')
      formatted_to = "+#{formatted_to}"
    end
    
    # Build JSON payload for the API
    payload = {
      messages: [
        {
          source: 'ruby_app',
          from:   from,
          body:   encoded_body,
          to:     formatted_to
        }
      ]
    }

    Rails.logger.info("[ClicksendClient] Sending SMS from '#{from}' to '#{formatted_to}'")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri, {
      'Authorization' => "Basic #{auth}",
      'Content-Type'  => 'application/json'
    })
    request.body = payload.to_json

    begin
      response = http.request(request)
    rescue StandardError => e
      Rails.logger.error("[ClicksendClient] HTTP request failed: #{e.message}")
      return false
    end

    Rails.logger.debug("[ClicksendClient] code=#{response.code}, body=#{response.body}")

    if response.code.to_i == 200
      json = JSON.parse(response.body) rescue {}
      if json["response_code"] == "SUCCESS"
        Rails.logger.info("[ClicksendClient] Sent SMS to #{to}")
        true
      else
        Rails.logger.error("[ClicksendClient] Error response: #{response.body}")
        false
      end
    else
      Rails.logger.error("[ClicksendClient] HTTP Error code=#{response.code}")
      false
    end
  end
end
