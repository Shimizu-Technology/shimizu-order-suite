# app/controllers/users_controller.rb
class UsersController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request, only: [ :show_profile, :update_profile, :verify_phone, :resend_code, :index, :show ]
  before_action :require_admin_or_staff, only: [ :index, :show ]
  before_action :ensure_tenant_context, except: [:create]

  # POST /signup
  def create
    # Prepare user parameters
    create_params = user_params
    
    # Default role to 'customer' if not provided
    create_params[:role] = "customer" if create_params[:role].blank?
    
    # IMPORTANT: For multi-tenant user creation, we need to use the frontend context
    # This allows the same email to be used across different restaurants
    frontend_restaurant_id = request.headers['X-Frontend-Restaurant-ID']
    
    if frontend_restaurant_id.present?
      # Override the restaurant_id with the one from the frontend context
      create_params[:restaurant_id] = frontend_restaurant_id
    elsif !create_params[:restaurant_id]
      # Fallback only if no restaurant_id is specified anywhere
      default_rest = Restaurant.find_by(name: "Hafaloha")
      create_params[:restaurant_id] = default_rest.id if default_rest
    end
    
    # We'll set phone_verified = false initially
    create_params[:phone_verified] = false
    
    # If user provided a phone, generate a verification code
    if create_params[:phone].present?
      code = generate_code
      create_params[:verification_code] = code
      create_params[:verification_code_sent_at] = Time.current
    end
    
    # Set the current_restaurant for the service
    requested_restaurant = Restaurant.find_by(id: create_params[:restaurant_id])
    
    # Important: We need to ensure we're using the restaurant from params, not from tenant context
    # This allows users to be created for a specific restaurant, even if the request comes from another
    @current_restaurant = requested_restaurant
    
    # Create the user using the service, but don't override the restaurant_id
    # This is crucial for multi-tenant user creation with the same email
    result = user_service.create_user(create_params, preserve_restaurant_id: true)
    
    if result[:success]
      user = result[:user]
      
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
      
      # Generate JWT token using TokenService
      token = TokenService.generate_token(user)
      render json: { jwt: token, user: user }, status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
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
    # Prepare filters
    filters = {}
    
    # Filter by role if specified
    filters[:role] = params[:role] if params[:role].present?
    
    # Filter by multiple roles if specified
    if params[:roles].present?
      # Convert to array if it's a string
      filters[:role] = params[:roles].is_a?(Array) ? params[:roles] : [params[:roles]]
    end
    
    # Add search filter if specified
    filters[:search] = params[:search] if params[:search].present?
    
    # Add pagination parameters
    filters[:page] = params[:page] || 1
    filters[:per_page] = params[:per_page] || 20
    
    # Get users from service
    result = user_service.list_users(filters)
    
    if result[:success]
      # For the staff filter in OrderManager, we need to return just the array of users
      if params[:roles].present?
        render json: result[:users]
      else
        # For other cases, return the paginated response with metadata
        render json: {
          users: result[:users],
          total_count: result[:meta][:total_count],
          page: result[:meta][:page],
          per_page: result[:meta][:per_page],
          total_pages: result[:meta][:total_pages]
        }
      end
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :internal_server_error
    end
  end

  # GET /users/:id
  # Get a specific user
  def show
    result = user_service.find_user(params[:id])
    
    if result[:success]
      render json: result[:user]
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :not_found
    end
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
      :password_confirmation,
      :restaurant_id
    )

    # For security, ensure role is always 'customer' for user signup
    permitted[:role] = "customer"

    permitted
  end

  def generate_code
    # 6-digit random code
    rand(100000..999999).to_s
  end
  
  # Get the user service instance
  def user_service
    @user_service ||= begin
      service = UserService.new(current_restaurant || @current_restaurant)
      service.current_user = current_user
      service
    end
  end
  
  # Ensure we have a tenant context
  def ensure_tenant_context
    unless current_restaurant.present? || @current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
end
