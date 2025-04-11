# app/controllers/admin/users_controller.rb

module Admin
  class UsersController < ApplicationController
    include TenantIsolation
    
    before_action :authorize_request
    before_action :require_admin!
    before_action :ensure_tenant_context

    # GET /admin/users?search=...&role=...&page=1&per_page=10&sort_by=email&sort_dir=asc&exclude_super_admin=true
    def index
      # Set current_user for the service
      user_management_service.current_user = current_user
      
      # Use the UserManagementService to get users with tenant isolation
      result = user_management_service.list_users(params)
      
      render json: result
    end

    # POST /admin/users
    def create
      # Set current_user for the service
      user_management_service.current_user = current_user
      
      # Use the UserManagementService to create a user with tenant isolation
      result = user_management_service.create_user(user_params, current_user)
      
      if result[:success]
        render json: result[:user], status: result[:status] || :created
      else
        render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
      end
    end

    # PATCH /admin/users/:id
    def update
      # Set current_user for the service
      user_management_service.current_user = current_user
      
      # Use the UserManagementService to update a user with tenant isolation
      result = user_management_service.update_user(params[:id], user_params, current_user)
      
      if result[:success]
        render json: result[:user]
      else
        render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
      end
    end

    # DELETE /admin/users/:id
    def destroy
      # Set current_user for the service
      user_management_service.current_user = current_user
      
      # Use the UserManagementService to delete a user with tenant isolation
      result = user_management_service.delete_user(params[:id], current_user)
      
      if result[:success]
        head :no_content
      else
        render json: { error: result[:error] }, status: result[:status] || :unprocessable_entity
      end
    end

  # POST /admin/users/:id/resend_invite
  def resend_invite
    # Use the UserManagementService to resend an invitation with tenant isolation
    result = user_management_service.resend_invite(params[:id])
    
    render json: { message: result[:message] }, status: :ok
  end

  # POST /admin/users/:id/admin_reset_password
  def admin_reset_password
    # Use the UserManagementService to reset a password with tenant isolation
    result = user_management_service.reset_password(params[:id], params[:password])
    
    if result[:success]
      render json: { message: result[:message] }, status: :ok
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  private

    def require_admin!
      unless current_user && current_user.role.in?(%w[admin super_admin])
        render json: { error: "Forbidden" }, status: :forbidden
      end
    end
    
    def user_management_service
      @user_management_service ||= UserManagementService.new(current_restaurant)
    end
    
    def ensure_tenant_context
      unless current_restaurant.present?
        render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
      end
    end

    # Admin can't directly set user password => no :password param
    def user_params
      # Explicitly permit all parameters to avoid unpermitted parameters warning
      # This doesn't affect security as we're still filtering what goes into the final permitted hash
      params.permit!  # This permits all parameters to avoid the warning
      
      # Handle both direct parameters and nested user parameters
      user_attributes = params[:user].present? ? params[:user].to_h.slice(:email, :first_name, :last_name, :phone, :role, :restaurant_id) : {}
      
      # Merge with direct parameters (direct parameters take precedence)
      permitted = params.to_h.slice(:email, :first_name, :last_name, :phone, :restaurant_id)
      permitted.merge!(user_attributes.select { |k, v| permitted[k.to_sym].nil? })

      # For role, ensure we're not creating a user with higher privileges than the current user
      role_param = params[:role].presence || user_attributes[:role].presence
      
      if role_param.present?
        # Allow super_admin role only for super_admin users
        if role_param == 'super_admin' && current_user.super_admin?
          permitted[:role] = role_param
        # Allow customer, staff, or admin roles for admin or super_admin users
        elsif role_param.in?(%w[customer staff admin]) && current_user.admin_or_above?
          permitted[:role] = role_param
        else
          # Default to customer if an invalid role is provided or user doesn't have permission
          permitted[:role] = "customer"
        end
      end

      permitted
    end
  end
end
