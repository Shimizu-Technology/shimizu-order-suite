# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  before_action :authorize_request, only: [:destroy, :validate]
  
  # Mark create, destroy, and validate as public endpoints that don't require restaurant context
  def public_endpoint?
    action_name.in?(['create', 'destroy', 'validate'])
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
      
      # Exclude password_digest from the response
      user_json = user.as_json.except('password_digest')
      render json: { token: token, user: user_json }, status: :created
    else
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end
  
  # DELETE /logout
  def destroy
    # In a real implementation, you might blacklist the token or perform other cleanup
    render json: { message: 'Logged out successfully' }, status: :ok
  end
  
  # GET /validate
  def validate
    user_json = @current_user.as_json.except('password_digest')
    render json: { user: user_json }, status: :ok
  end
end
