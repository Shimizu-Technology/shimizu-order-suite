# app/controllers/users_controller.rb

class UsersController < ApplicationController
  # For profile endpoints, require login
  before_action :authorize_request, only: [:show_profile, :update_profile]

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

  # GET /profile
  def show_profile
    # current_user is set by authorize_request
    render json: current_user, status: :ok
  end

  # PATCH /profile
  def update_profile
    # If the user wants to change password, handle that
    if params[:password].present?
      current_user.password = params[:password]
      # If you want a password_confirmation, handle it as well
      # current_user.password_confirmation = params[:password_confirmation]
    end

    # Then update other fields (phone, email, first_name, last_name, etc.)
    if current_user.update(profile_params)
      render json: current_user, status: :ok
    else
      render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  # The original user_params was for signup. For the profile update, let’s use a separate method:
  def profile_params
    params.permit(:first_name, :last_name, :email, :phone)
  end

  def user_params
    # For signup
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
