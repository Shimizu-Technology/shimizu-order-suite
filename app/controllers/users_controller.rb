# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authorize_request, only: [ :show_profile, :update_profile, :verify_phone, :resend_code, :index, :show ]
  before_action :require_admin_or_staff, only: [ :index, :show ]

  # Mark create, verify_phone, resend_code, show_profile, update_profile, index, and show as public endpoints that don't require restaurant context
  def public_endpoint?
    action_name.in?([ "create", "verify_phone", "resend_code", "show_profile", "update_profile", "index", "show" ])
  end

  # POST /signup
  def create
    user = User.new(user_params)

    # Default role to 'customer' if not provided
    user.role = "customer" if user.role.blank?

    # Assign a fallback restaurant if none specified
    unless user.restaurant_id
      default_rest = Restaurant.find_by(name: "Hafaloha")
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
        restaurant = Restaurant.find(user.restaurant_id)
        restaurant_name = restaurant.name
        # Use custom SMS sender ID if set, otherwise use restaurant name
        sms_sender = restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name

        SendSmsJob.perform_later(
          to:   user.phone,
          body: "Your verification code is #{user.verification_code}",
          from: sms_sender
        )
      end

      # Issue JWT with user_id, restaurant_id, role, and 24-hour expiration
      token_payload = {
        user_id: user.id,
        restaurant_id: user.restaurant_id,
        role: user.role,
        exp: 24.hours.from_now.to_i
      }

      token = JWT.encode(token_payload, Rails.application.secret_key_base)
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
    restaurant = Restaurant.find(user.restaurant_id)
    restaurant_name = restaurant.name
    # Use custom SMS sender ID if set, otherwise use restaurant name
    sms_sender = restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name

    SendSmsJob.perform_later(
      to:   user.phone,
      body: "Your new verification code is #{new_code}",
      from: sms_sender
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

  # GET /users
  # List users with optional filtering
  def index
    # Start with users from the current restaurant if available
    @users = if current_user&.restaurant_id
               User.where(restaurant_id: current_user.restaurant_id)
             else
               User.all
             end

    # Filter by role if specified
    if params[:role].present?
      @users = @users.where(role: params[:role])
    end
    
    # Filter by multiple roles if specified
    if params[:roles].present?
      # Convert to array if it's a string
      roles = params[:roles].is_a?(Array) ? params[:roles] : [params[:roles]]
      @users = @users.where(role: roles)
    end

    # Exclude specific roles if specified
    if params[:exclude_role].present?
      @users = @users.where.not(role: params[:exclude_role])
    end

    # Filter for users not already assigned to staff members
    if params[:available_for_staff].present? && params[:available_for_staff] == 'true'
      # Get IDs of users already assigned to staff members
      assigned_user_ids = StaffMember.where.not(user_id: nil).pluck(:user_id)
      @users = @users.where.not(id: assigned_user_ids)
    end

    # Include a specific user ID even if it's already assigned
    if params[:include_user_id].present?
      included_user = User.find_by(id: params[:include_user_id])
      @users = @users.or(User.where(id: included_user.id)) if included_user
    end

    # Pagination
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i
    total_count = @users.count

    @users = @users.order(:first_name, :last_name).offset((page - 1) * per_page).limit(per_page)

    # For the staff filter in OrderManager, we need to return just the array of users
    if params[:roles].present?
      render json: @users
    else
      # For other cases, return the paginated response with metadata
      render json: {
        users: @users,
        total_count: total_count,
        page: page,
        per_page: per_page,
        total_pages: (total_count.to_f / per_page).ceil
      }
    end
  end

  # GET /users/:id
  # Get a specific user
  def show
    user = User.find(params[:id])
    render json: user
  end

  private

  def require_admin
    unless current_user&.role.in?(%w[admin super_admin])
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def profile_params
    params.require(:user).permit(:first_name, :last_name, :email, :phone)
  end

  def user_params
    # Only allow basic user information for signup
    permitted = params.require(:user).permit(
      :first_name,
      :last_name,
      :phone,
      :email,
      :password,
      :password_confirmation
    )

    # For security, ensure role is always 'customer' for user signup
    permitted[:role] = "customer"

    permitted
  end

  def generate_code
    # 6-digit random code
    rand(100000..999999).to_s
  end
end
