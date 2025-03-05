# spec/support/request_spec_helper.rb
module RequestSpecHelper
  # Parse JSON response to Ruby hash
  def json
    JSON.parse(response.body)
  end

  # Helper method to set auth headers
  def auth_headers(user)
    token = JWT.encode({ user_id: user.id }, Rails.application.credentials.secret_key_base)
    { 'Authorization' => "Bearer #{token}" }
  end
end
