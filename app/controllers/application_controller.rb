# app/controllers/application_controller.rb

class ApplicationController < ActionController::API
  def authorize_request
    header = request.headers['Authorization']
    token  = header&.split(' ')&.last

    if token.blank?
      return render json: { error: 'Missing token' }, status: :unauthorized
    end

    begin
      decoded = verify_auth0_token(token)

      # Link to local user if you want:
      sub   = decoded['sub']  # e.g. "auth0|123456789"
      email = decoded['email'] # might or might not exist

      @current_user = User.find_or_create_by!(auth0_sub: sub) do |user|
        # Set default fields if user is new
        user.email       = email if email
        user.first_name  = decoded['given_name']  || 'Auth0'
        user.last_name   = decoded['family_name'] || 'User'
        # You can set a random password, so has_secure_password won't fail:
        user.password_digest = SecureRandom.hex(32)
      end

    rescue => e
      Rails.logger.error("Auth error: #{e.message}")
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end

  def current_user
    @current_user
  end
end
