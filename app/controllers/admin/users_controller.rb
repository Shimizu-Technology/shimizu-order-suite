# app/controllers/admin/users_controller.rb

module Admin
  class UsersController < ApplicationController
    before_action :authorize_request
    before_action :require_admin!

    # Mark all actions as public endpoints that don't require restaurant context
    def public_endpoint?
      true
    end

    # GET /admin/users?search=...&role=...&page=1&per_page=10&sort_by=email&sort_dir=asc&exclude_super_admin=true
    def index
      # Pagination
      page     = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 10).to_i

      # Sorting
      # For simplicity, let's allow only a couple of fields, e.g. email or created_at.
      sort_by  = params[:sort_by].presence_in(%w[email created_at]) || "created_at"
      sort_dir = params[:sort_dir] == "asc" ? "asc" : "desc"

      # Start building query
      users = policy_scope(User).order("#{sort_by} #{sort_dir}")

      # Search filter
      if params[:search].present?
        q = "%#{params[:search].downcase}%"
        users = users.where(
          "lower(email) LIKE ? OR lower(first_name) LIKE ? OR lower(last_name) LIKE ?",
          q, q, q
        )
      end

      # Role filter
      if params[:role].present? && params[:role] != "all"
        users = users.where(role: params[:role])
      end
      
      # Exclude super_admin users for non-super_admin users
      if params[:exclude_super_admin] == 'true' && !current_user.super_admin?
        users = users.where.not(role: 'super_admin')
      end

      total_count = users.count

      # Apply pagination
      users = users.offset((page - 1) * per_page).limit(per_page)

      render json: {
        users: users,
        total_count: total_count,
        page: page,
        per_page: per_page
      }
    end

    # POST /admin/users
    def create
      user = User.new(user_params)
      
      # Authorize the user creation
      authorize user
      
      # Check if trying to create super_admin when not authorized
      if user.role == 'super_admin' && !current_user.super_admin?
        return render json: { errors: ["Only Super Admins can create Super Admin accounts"] }, status: :forbidden
      end

      # If admin didn't supply a password => generate random
      if params[:password].blank?
        user.password = SecureRandom.hex(10)  # random 20-char hex
        user.skip_password_validation = true
      end

      if user.save
        # Now send them an invite link (re-using your reset-password flow).
        raw_token = user.generate_reset_password_token!
        PasswordMailer.reset_password(user, raw_token).deliver_later

        render json: user, status: :created
      else
        render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH /admin/users/:id
    def update
      user = User.find(params[:id])
      
      # Authorize the user update
      authorize user
      
      # Check if trying to update to super_admin when not authorized
      if params[:role] == 'super_admin' && !current_user.super_admin?
        return render json: { errors: ["Only Super Admins can assign the Super Admin role"] }, status: :forbidden
      end
      
      # Prevent non-super_admin from updating super_admin users
      if user.role == 'super_admin' && !current_user.super_admin?
        return render json: { errors: ["You do not have permission to edit Super Admin users"] }, status: :forbidden
      end
      
      if user.update(user_params)
        render json: user
      else
        render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /admin/users/:id
    def destroy
      user = User.find(params[:id])

      # Prevent deleting self
      if user.id == current_user.id
        return render json: { error: "Cannot delete your own account" }, status: :unprocessable_entity
      end

      # Check if this is the last admin
      if user.role.in?(%w[admin super_admin]) && User.where(role: %w[admin super_admin]).count <= 1
        return render json: { error: "Cannot delete the last admin user" }, status: :unprocessable_entity
      end

      begin
        # Start a transaction
        ActiveRecord::Base.transaction do
          # Nullify user_id in associated orders
          Order.where(user_id: user.id).update_all(user_id: nil)

          # Now delete the user
          user.destroy!
        end

        head :no_content
      rescue => e
        Rails.logger.error("Failed to delete user: #{e.message}")
        render json: { error: "Failed to delete user: #{e.message}" }, status: :unprocessable_entity
      end
    end

  # POST /admin/users/:id/resend_invite
  def resend_invite
    user = User.find(params[:id])
    # Re-generate reset token & re-send the same "reset password" email
    raw_token = user.generate_reset_password_token!
    PasswordMailer.reset_password(user, raw_token).deliver_later

    render json: { message: "Invitation re-sent to #{user.email}" }, status: :ok
  end

  # POST /admin/users/:id/admin_reset_password
  def admin_reset_password
    user = User.find(params[:id])

    # Get the password from params
    new_password = params[:password]

    # Validate password
    if new_password.blank? || new_password.length < 6
      return render json: { errors: [ "Password must be at least 6 characters" ] }, status: :unprocessable_entity
    end

    # Update the user's password
    user.password = new_password

    if user.save
      render json: {
        message: "Password has been reset successfully"
      }, status: :ok
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

    def require_admin!
      unless current_user && current_user.role.in?(%w[admin super_admin])
        render json: { error: "Forbidden" }, status: :forbidden
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
