# app/services/user_service.rb
class UserService < TenantScopedService
  attr_accessor :current_user

  # List all users for the current restaurant
  def list_users(filters = {})
    begin
      query = scope_query(User)
      
      # Special handling for staff assignment filtering
      if filters[:available_for_staff]
        # Get users who are not already assigned to staff members
        assigned_user_ids = StaffMember.where(restaurant_id: restaurant.id)
                                      .where.not(user_id: nil)
                                      .pluck(:user_id)
        
        # If we need to include a specific user_id (for editing), add it to the query
        if filters[:include_user_id].present?
          query = query.where("id NOT IN (?) OR id = ?", assigned_user_ids, filters[:include_user_id])
        else
          query = query.where.not(id: assigned_user_ids) if assigned_user_ids.any?
        end
        
        # Exclude specific roles if requested
        if filters[:exclude_role].present?
          exclude_roles = filters[:exclude_role].is_a?(Array) ? filters[:exclude_role] : [filters[:exclude_role]]
          query = query.where.not(role: exclude_roles)
        end
      end
      
      # Apply role filter if provided (and not in staff assignment mode)
      if filters[:role].present? && !filters[:available_for_staff]
        query = query.where(role: filters[:role])
      end
      
      # Apply status filter if provided
      if filters[:status].present?
        query = query.where(status: filters[:status])
      end
      
      # Apply search filter if provided
      if filters[:search].present?
        search_term = "%#{filters[:search]}%"
        query = query.where("first_name ILIKE ? OR last_name ILIKE ? OR email ILIKE ?", search_term, search_term, search_term)
      end
      
      # Apply pagination
      page = filters[:page] || 1
      per_page = filters[:per_page] || 20
      
      total_count = query.count
      users = query.order(created_at: :desc).limit(per_page).offset((page.to_i - 1) * per_page.to_i)
      
      {
        success: true,
        users: users,
        meta: {
          total_count: total_count,
          page: page.to_i,
          per_page: per_page.to_i,
          total_pages: (total_count.to_f / per_page.to_i).ceil
        }
      }
    rescue => e
      { success: false, errors: ["Failed to fetch users: #{e.message}"], status: :internal_server_error }
    end
  end

  # Find a specific user by ID
  def find_user(id)
    begin
      user = scope_query(User).find_by(id: id)
      
      if user.nil?
        return { success: false, errors: ["User not found"], status: :not_found }
      end
      
      { success: true, user: user }
    rescue => e
      { success: false, errors: ["Failed to fetch user: #{e.message}"], status: :internal_server_error }
    end
  end

  # Create a new user
  def create_user(user_params, preserve_restaurant_id: false)
    begin
      # Only override restaurant_id if not explicitly preserving it
      # This is important for multi-tenant user creation with the same email
      unless preserve_restaurant_id
        user_params[:restaurant_id] = restaurant.id
      end
      
      # Create the user
      user = User.new(user_params)
      
      if user.save
        { success: true, user: user }
      else
        { success: false, errors: user.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to create user: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Update an existing user
  def update_user(id, user_params)
    begin
      user = scope_query(User).find_by(id: id)
      
      if user.nil?
        return { success: false, errors: ["User not found"], status: :not_found }
      end
      
      # Don't allow changing the restaurant_id
      user_params.delete(:restaurant_id)
      
      # Special handling for password updates
      if user_params[:password].blank?
        user_params.delete(:password)
        user_params.delete(:password_confirmation)
      end
      
      if user.update(user_params)
        { success: true, user: user }
      else
        { success: false, errors: user.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to update user: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Delete a user
  def delete_user(id)
    begin
      user = scope_query(User).find_by(id: id)
      
      if user.nil?
        return { success: false, errors: ["User not found"], status: :not_found }
      end
      
      # Don't allow deleting yourself
      if user.id == current_user&.id
        return { success: false, errors: ["Cannot delete your own account"], status: :unprocessable_entity }
      end
      
      # Don't allow deleting the last admin
      if user.role == "admin" && scope_query(User).where(role: "admin").count <= 1
        return { success: false, errors: ["Cannot delete the last admin user"], status: :unprocessable_entity }
      end
      
      user.destroy
      { success: true }
    rescue => e
      { success: false, errors: ["Failed to delete user: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Change user status (activate/deactivate)
  def change_user_status(id, status)
    begin
      user = scope_query(User).find_by(id: id)
      
      if user.nil?
        return { success: false, errors: ["User not found"], status: :not_found }
      end
      
      # Don't allow changing your own status
      if user.id == current_user&.id
        return { success: false, errors: ["Cannot change your own status"], status: :unprocessable_entity }
      end
      
      # Don't allow deactivating the last admin
      if status == "inactive" && user.role == "admin" && scope_query(User).where(role: "admin", status: "active").count <= 1
        return { success: false, errors: ["Cannot deactivate the last admin user"], status: :unprocessable_entity }
      end
      
      if user.update(status: status)
        { success: true, user: user }
      else
        { success: false, errors: user.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to change user status: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Change user role
  def change_user_role(id, role)
    begin
      user = scope_query(User).find_by(id: id)
      
      if user.nil?
        return { success: false, errors: ["User not found"], status: :not_found }
      end
      
      # Don't allow changing your own role
      if user.id == current_user&.id
        return { success: false, errors: ["Cannot change your own role"], status: :unprocessable_entity }
      end
      
      # Don't allow demoting the last admin
      if user.role == "admin" && role != "admin" && scope_query(User).where(role: "admin").count <= 1
        return { success: false, errors: ["Cannot demote the last admin user"], status: :unprocessable_entity }
      end
      
      if user.update(role: role)
        { success: true, user: user }
      else
        { success: false, errors: user.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to change user role: #{e.message}"], status: :internal_server_error }
    end
  end
end
