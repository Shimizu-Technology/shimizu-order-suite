# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  # POST /login
  def create
    # 1) We downcase the param => "john@EXAMPLE.com" => "john@example.com"
    # 2) Find by LOWER(email) = downcased param
    user = User.find_by(
      "LOWER(email) = ?", 
      params[:email].to_s.downcase
    )

    if user && user.authenticate(params[:password])
      token = JWT.encode({ user_id: user.id }, Rails.application.secret_key_base)
      render json: { jwt: token, user: user }, status: :created
    else
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end
end
