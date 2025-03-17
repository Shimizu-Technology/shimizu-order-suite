# app/controllers/passwords_controller.rb

class PasswordsController < ApplicationController
  # Mark forgot and reset as public endpoints that don't require restaurant context
  def public_endpoint?
    action_name.in?([ "forgot", "reset" ])
  end

  # POST /password/forgot
  def forgot
    user = User.find_by(email: params[:email].to_s.downcase)
    if user
      # 1) Generate the reset token
      raw_token = user.generate_reset_password_token!

      # 2) Send the email with the raw token
      PasswordMailer.reset_password(user, raw_token).deliver_later
    end

    # Return a generic message to avoid email enumeration
    render json: { message: "If that email exists, a reset link has been sent." }
  end

  # PATCH /password/reset
  def reset
    # Because we encoded email, Rails automatically decodes it here.
    user = User.find_by(email: params[:email].to_s.downcase)
    unless user
      return render json: { error: "Invalid link or user not found" }, status: :unprocessable_entity
    end

    # Check if the token is valid & not expired
    unless user.reset_token_valid?(params[:token])
      return render json: { error: "Invalid or expired token" }, status: :unprocessable_entity
    end

    # Update the user’s password
    user.password = params[:new_password]
    user.password_confirmation = params[:new_password_confirmation]

    if user.save
      # Clear token so it can’t be reused
      user.clear_reset_password_token!

      # Generate a new JWT so the user can be auto-logged in
      jwt = JWT.encode({ user_id: user.id }, Rails.application.secret_key_base)

      # Return both the token and the user object => front end can store them
      render json: {
        message: "Password updated successfully.",
        jwt: jwt,
        user: user
      }, status: :ok
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
