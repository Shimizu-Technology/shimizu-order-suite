# app/controllers/passwords_controller.rb

class PasswordsController < ApplicationController
  include TenantIsolation
  
  # Override global_access_permitted to allow password reset endpoints to work without a tenant context
  def global_access_permitted?
    action_name.in?([ "forgot", "reset" ])
  end
  
  # Skip ensure_tenant_context for password reset actions
  skip_before_action :set_current_tenant, only: [:forgot, :reset]

  # POST /password/forgot
  def forgot
    # Extract restaurant_id from params or headers
    restaurant_id = params[:restaurant_id] || request.headers['X-Frontend-Restaurant-ID']
    
    # Use the PasswordService to handle the forgot password request with restaurant context
    result = password_service.forgot_password(params[:email], restaurant_id)
    
    if result[:success]
      render json: { message: result[:message] }
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :internal_server_error
    end
  end

  # PATCH /password/reset
  def reset
    # Extract restaurant_id from params or headers
    restaurant_id = params[:restaurant_id] || request.headers['X-Frontend-Restaurant-ID']
    
    # Use the PasswordService to handle the password reset with restaurant context
    result = password_service.reset_password(
      params[:email],
      params[:token],
      params[:new_password],
      params[:new_password_confirmation],
      restaurant_id
    )
    
    if result[:success]
      render json: {
        message: result[:message],
        jwt: result[:token],
        user: result[:user]
      }, status: :ok
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  private
  
  # Get the password service instance
  def password_service
    @password_service ||= PasswordService.new(analytics)
  end
end
