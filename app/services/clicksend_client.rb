# app/services/clicksend_client.rb
require 'net/http'
require 'json'
require 'base64'

class ClicksendClient
  BASE_URL = 'https://rest.clicksend.com/v3'

  def self.send_text_message(to:, body:, from: nil)
    username = ENV['CLICKSEND_USERNAME']
    api_key  = ENV['CLICKSEND_API_KEY']

    if username.blank? || api_key.blank?
      Rails.logger.error("[ClicksendClient] Missing ClickSend credentials.")
      return false
    end

    # Basic Auth
    auth = Base64.strict_encode64("#{username}:#{api_key}")
    uri  = URI("#{BASE_URL}/sms/send")

    # Build JSON payload for the API
    payload = {
      messages: [
        {
          source: 'ruby_app',
          from:   from, # e.g. 'RotarySushi'
          body:   body,
          to:     to
        }
      ]
    }

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
