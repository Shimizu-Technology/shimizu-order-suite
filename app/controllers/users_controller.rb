# app/controllers/users_controller.rb

class UsersController < ApplicationController
  # POST /signup
  def create
    user = User.new(user_params)

    # Default role to 'customer' if not provided
    user.role = 'customer' if user.role.blank?

    # Assign a fallback restaurant if none specified
    unless user.restaurant_id
      default_rest = Restaurant.find_by(name: 'Rotary Sushi')
      user.restaurant_id = default_rest.id if default_rest
    end

    if user.save
      # Issue JWT
      token = JWT.encode({ user_id: user.id }, Rails.application.secret_key_base)
      render json: { jwt: token, user: user }, status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  # Expect nested params => { user: {...} }
  def user_params
    params.require(:user).permit(
      :first_name,
      :last_name,
      :phone,
      :email,
      :password,
      :password_confirmation,
      :restaurant_id,
      :role
    )
  end
end
