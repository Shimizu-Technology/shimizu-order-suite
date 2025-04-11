# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  include TenantIsolation
  
  # Override global_access_permitted to allow authentication endpoints to work without a tenant context
  def global_access_permitted?
    action_name.in?(["create", "destroy"])
  end
  
  # Skip ensure_tenant_context for login and logout actions
  skip_before_action :set_current_tenant, only: [:create, :destroy]

  # POST /login
  def create
    # Use the SessionService to authenticate the user
    result = session_service.authenticate(params[:email], params[:password])
    
    if result[:success]
      render json: { jwt: result[:token], user: result[:user] }, status: :created
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :unauthorized
    end
  end
  
  # DELETE /logout
  def destroy
    # Get token from Authorization header
    header = request.headers["Authorization"]
    token = header.split(" ").last if header
    
    # Use the SessionService to log out the user
    result = session_service.logout(token, current_user)
    
    if result[:success]
      render json: { message: result[:message] }, status: :ok
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :internal_server_error
    end
  end
  
  # POST /switch-tenant
  def switch_tenant
    # Ensure user is authenticated
    return render json: { error: "Unauthorized" }, status: :unauthorized unless current_user
    
    # Get the requested restaurant_id
    restaurant_id = params[:restaurant_id].to_i
    
    # Get token from Authorization header
    header = request.headers["Authorization"]
    current_token = header.split(" ").last if header
    
    # Use the SessionService to switch tenant
    result = session_service.switch_tenant(current_user, restaurant_id, current_token)
    
    if result[:success]
      render json: { jwt: result[:token], user: result[:user] }, status: :created
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :forbidden
    end
  end
  
  private
  
  # Get the session service instance
  def session_service
    @session_service ||= SessionService.new(analytics)
  end
end
