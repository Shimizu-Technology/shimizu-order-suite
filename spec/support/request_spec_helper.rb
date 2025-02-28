module RequestSpecHelper
  # Parse JSON response to Ruby hash
  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end
  
  # Helper method to generate auth tokens for test users
  def auth_headers_for(user)
    token = JWT.encode(
      { user_id: user.id, exp: 24.hours.from_now.to_i },
      Rails.application.credentials.secret_key_base
    )
    { 'Authorization' => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include RequestSpecHelper, type: :request
  config.include RequestSpecHelper, type: :controller
end
