# app/services/user_management_service.rb
class UserManagementService < TenantScopedService
  # Get users with pagination, filtering, and sorting
  def list_users(params)
    # Pagination
    page     = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 10).to_i

    # Sorting
    sort_by  = params[:sort_by].presence_in(%w[email created_at]) || "created_at"
    sort_dir = params[:sort_dir] == "asc" ? "asc" : "desc"

    # Start building query with tenant scoping
    users = scope_query(User).order("#{sort_by} #{sort_dir}")

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

    {
      users: users,
      total_count: total_count,
      page: page,
      per_page: per_page
    }
  end

  # Create a new user
  def create_user(user_params, current_user)
    user = User.new(user_params)
    
    # Set restaurant_id to current restaurant if not explicitly set
    user.restaurant_id ||= @restaurant.id
    
    # Check if trying to create super_admin when not authorized
    if user.role == 'super_admin' && !current_user.super_admin?
      return { success: false, errors: ["Only Super Admins can create Super Admin accounts"], status: :forbidden }
    end

    # Track whether admin provided a password
    password_provided = user_params[:password].present?
    
    # If admin didn't supply a password => generate random and prepare for invite email
    if user_params[:password].blank?
      user.password = SecureRandom.hex(10)  # random 20-char hex
      user.skip_password_validation = true
    end

    if user.save
      # Only send invite email if no password was provided by admin
      if !password_provided
        # Send them an invite link (re-using your reset-password flow)
        raw_token = user.generate_reset_password_token!
        PasswordMailer.reset_password(user, raw_token).deliver_later
      end
      
      { success: true, user: user, status: :created }
    else
      { success: false, errors: user.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Update an existing user
  def update_user(user_id, user_params, current_user)
    user = scope_query(User).find(user_id)
    
    # Check if trying to update to super_admin when not authorized
    if user_params[:role] == 'super_admin' && !current_user.super_admin?
      return { success: false, errors: ["Only Super Admins can assign the Super Admin role"], status: :forbidden }
    end
    
    # Prevent non-super_admin from updating super_admin users
    if user.role == 'super_admin' && !current_user.super_admin?
      return { success: false, errors: ["You do not have permission to edit Super Admin users"], status: :forbidden }
    end
    
    if user.update(user_params)
      { success: true, user: user }
    else
      { success: false, errors: user.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Delete a user
  def delete_user(user_id, current_user)
    user = scope_query(User).find(user_id)

    # Prevent deleting self
    if user.id == current_user.id
      return { success: false, error: "Cannot delete your own account", status: :unprocessable_entity }
    end

    # Check if this is the last admin
    if user.role.in?(%w[admin super_admin]) && User.where(role: %w[admin super_admin]).count <= 1
      return { success: false, error: "Cannot delete the last admin user", status: :unprocessable_entity }
    end

    begin
      # Start a transaction
      ActiveRecord::Base.transaction do
        # Nullify user_id in associated orders
        scope_query(Order).where(user_id: user.id).update_all(user_id: nil)

        # Now delete the user
        user.destroy!
      end

      { success: true }
    rescue => e
      Rails.logger.error("Failed to delete user: #{e.message}")
      { success: false, error: "Failed to delete user: #{e.message}", status: :unprocessable_entity }
    end
  end

  # Resend invitation to a user
  def resend_invite(user_id)
    user = scope_query(User).find(user_id)
    
    # Re-generate reset token & re-send the same "reset password" email
    raw_token = user.generate_reset_password_token!
    PasswordMailer.reset_password(user, raw_token).deliver_later

    { success: true, message: "Invitation re-sent to #{user.email}" }
  end

  # Reset a user's password
  def reset_password(user_id, new_password)
    user = scope_query(User).find(user_id)

    # Validate password
    if new_password.blank? || new_password.length < 6
      return { success: false, errors: ["Password must be at least 6 characters"], status: :unprocessable_entity }
    end

    # Update the user's password
    user.password = new_password

    if user.save
      { success: true, message: "Password has been reset successfully" }
    else
      { success: false, errors: user.errors.full_messages, status: :unprocessable_entity }
    end
  end
  
  # Get the current user from the service context
  def current_user
    @current_user
  end
  
  # Set the current user for the service
  def current_user=(user)
    @current_user = user
  end
  
  private
end
