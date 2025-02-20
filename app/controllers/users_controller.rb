class UsersController < ApplicationController
  before_action :authorize_request, only: [:show_profile, :update_profile, :verify_phone, :resend_code]

  # POST /signup
  def create
    user = User.new(user_params)

    # Default role to 'customer' if not provided
    user.role = 'customer' if user.role.blank?

    # Assign a fallback restaurant if none specified
    unless user.restaurant_id
      default_rest = Restaurant.find_by(name: 'Hafaloha')
      user.restaurant_id = default_rest.id if default_rest
    end

    # We'll set phone_verified = false initially
    user.phone_verified = false

    # If user provided a phone, generate a verification code & send an SMS
    if user.phone.present?
      code = generate_code
      user.verification_code = code
      user.verification_code_sent_at = Time.current
    end

    if user.save
      # If phone present => send the SMS code
      if user.phone.present?
        SendSmsJob.perform_later(
          to:   user.phone,
          body: "Your verification code is #{user.verification_code}",
          from: "Hafaloha"
        )
      end

      # Issue JWT
      token = JWT.encode({ user_id: user.id }, Rails.application.secret_key_base)
      render json: { jwt: token, user: user }, status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /verify_phone
  # Requires the user to be logged in (authorize_request)
  def verify_phone
    user = current_user
    return render json: { error: "Unauthorized" }, status: :unauthorized unless user

    code = params[:code].to_s.strip
    if code.blank?
      return render json: { error: "Verification code is required" }, status: :unprocessable_entity
    end

    # Check if code is expired (optional 10 min window)
    if user.verification_code_sent_at && user.verification_code_sent_at < 10.minutes.ago
      return render json: { error: "Verification code expired, please request a new one" }, status: :unprocessable_entity
    end

    if user.verification_code == code
      user.update(phone_verified: true, verification_code: nil, verification_code_sent_at: nil)
      render json: { message: "Phone verified successfully!", user: user }, status: :ok
    else
      render json: { error: "Invalid code" }, status: :unprocessable_entity
    end
  end

  # POST /resend_code
  def resend_code
    user = current_user
    return render json: { error: "Unauthorized" }, status: :unauthorized unless user

    # If they're already verified, no need to resend
    if user.phone_verified?
      return render json: { message: "Your phone is already verified" }, status: :ok
    end

    # If no phone, can't send
    unless user.phone.present?
      return render json: { error: "No phone number on file" }, status: :unprocessable_entity
    end

    # optional: throttle
    if user.verification_code_sent_at && user.verification_code_sent_at > 1.minute.ago
      return render json: { error: "Please wait before requesting another code" }, status: :too_many_requests
    end

    # Generate a new code
    new_code = generate_code
    user.update(
      verification_code: new_code,
      verification_code_sent_at: Time.current
    )

    # Send new SMS
    SendSmsJob.perform_later(
      to:   user.phone,
      body: "Your new verification code is #{new_code}",
      from: "Hafaloha"
    )
    render json: { message: "Verification code resent. Check your messages." }, status: :ok
  end

  # GET /profile
  def show_profile
    render json: current_user, status: :ok
  end

  # PATCH /profile
  def update_profile
    if params[:password].present?
      current_user.password = params[:password]
    end

    if current_user.update(profile_params)
      render json: current_user, status: :ok
    else
      render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(:first_name, :last_name, :email, :phone)
  end

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

  def generate_code
    # 6-digit random code
    rand(100000..999999).to_s
  end
end
