# spec/support/controller_spec_helper.rb
module ControllerSpecHelper
  # Generate tokens for test
  def token_generator(user_id)
    JWT.encode({ user_id: user_id }, Rails.application.secret_key_base)
  end

  # Generate expired tokens for test
  def expired_token_generator(user_id)
    JWT.encode(
      { user_id: user_id, exp: Time.now.to_i - 10 },
      Rails.application.secret_key_base
    )
  end

  # Return valid headers
  def valid_headers(user_id)
    {
      "Authorization" => "Bearer #{token_generator(user_id)}",
      "Content-Type" => "application/json"
    }
  end

  # Return invalid headers
  def invalid_headers
    {
      "Authorization" => nil,
      "Content-Type" => "application/json"
    }
  end
end
