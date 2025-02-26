# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  # Mark create as a public endpoint that doesn't require restaurant context
  def public_endpoint?
    action_name == 'create'
  end
  
  # POST /login
  def create
    # 1) We downcase the param => "john@EXAMPLE.com" => "john@example.com"
    # 2) Find by LOWER(email) = downcased param
    user = User.find_by(
      "LOWER(email) = ?", 
      params[:email].to_s.downcase
    )

    if user && user.authenticate(params[:password])
      # Create token with user_id, restaurant_id, and 24-hour expiration
      token_payload = {
        user_id: user.id,
        restaurant_id: user.restaurant_id,
        exp: 24.hours.from_now.to_i
      }
      
      token = JWT.encode(token_payload, Rails.application.secret_key_base)
      render json: { jwt: token, user: user }, status: :created
    else
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end
end
