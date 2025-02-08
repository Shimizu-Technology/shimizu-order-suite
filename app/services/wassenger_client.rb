# app/services/wassenger_client.rb
require 'net/http'
require 'json'

class WassengerClient
  BASE_URL = 'https://api.wassenger.com/v1'

  def initialize(api_token: ENV['WASSENGER_API_TOKEN'])
    @api_token = api_token
  end

  def send_group_message(group_wid, message)
    uri = URI.parse("#{BASE_URL}/messages")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Token']        = @api_token  # Wassenger expects `Token: ...`

    request.body = {
      group:   group_wid,
      message: message
      # You can also set "priority": "high", etc. if desired
    }.to_json

    response = http.request(request)
    # Optionally parse JSON:
    parsed = JSON.parse(response.body) rescue {}

    Rails.logger.info "[WassengerClient] group=#{group_wid} status=#{response.code} body=#{response.body}"

    if response.code.to_i >= 200 && response.code.to_i < 300
      # success
      parsed
    else
      # log or raise error
      Rails.logger.error "[WassengerClient] Error sending WhatsApp message: #{response.body}"
      parsed
    end
  end
end
