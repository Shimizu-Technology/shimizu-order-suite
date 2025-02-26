# app/controllers/application_controller.rb

class ApplicationController < ActionController::API
  include RestaurantScope
  def authorize_request
    header = request.headers['Authorization']
    token = header.split(' ').last if header

    begin
      decoded = JWT.decode(token, Rails.application.secret_key_base)[0]
      @current_user = User.find(decoded['user_id'])
      
      # Check token expiration if exp is present
      if decoded['exp'].present? && Time.at(decoded['exp']) < Time.current
        render json: { errors: 'Token expired' }, status: :unauthorized
        return
      end
    rescue ActiveRecord::RecordNotFound, JWT::DecodeError
      render json: { errors: 'Unauthorized' }, status: :unauthorized
    end
  end

  def current_user
    @current_user
  end

  # optional_authorize tries to decode the token if present but doesn't fail if invalid
  def optional_authorize
    header = request.headers['Authorization']
    token = header.split(' ').last if header
    return unless token  # no token => do nothing => user remains nil

    begin
      # Use the same decode logic & secret as authorize_request
      decoded = JWT.decode(token, Rails.application.secret_key_base)[0]
      @current_user = User.find(decoded['user_id'])
      
      # Check token expiration if exp is present
      return if decoded['exp'].present? && Time.at(decoded['exp']) < Time.current
    rescue ActiveRecord::RecordNotFound, JWT::DecodeError
      # do nothing => user stays nil
    end
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
