# app/services/staff_member_service.rb
class StaffMemberService
  attr_reader :current_restaurant, :analytics
  
  def initialize(current_restaurant, analytics_service = nil)
    @current_restaurant = current_restaurant
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Get all staff members with filtering, sorting, and pagination
  def list_staff_members(params, current_user)
    begin
      # Allow staff, admin, and super_admin users to access staff members
      unless current_user&.role.in?(%w[admin super_admin staff])
        return { success: false, errors: ["Unauthorized"], status: :unauthorized }
      end
      
      staff_members = StaffMember.where(restaurant_id: current_restaurant.id)
      
      # Filter by user_id if provided
      if params[:user_id].present?
        staff_members = staff_members.where(user_id: params[:user_id])
      end
      
      # Filter by active status if provided
      if params[:active].present?
        staff_members = staff_members.where(active: params[:active] == 'true')
      end
      
      # Filter by house account balance if provided
      if params[:with_balance].present? && params[:with_balance] == 'true'
        staff_members = staff_members.with_house_account_balance
      end
      
      # Search functionality
      if params[:search].present?
        search_term = "%#{params[:search]}%"
        staff_members = staff_members.where(
          "name ILIKE ? OR position ILIKE ?",
          search_term, search_term
        )
      end
      
      # Add pagination
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 20).to_i
      
      # Apply sorting
      sort_by = params[:sort_by] || 'name'
      sort_direction = params[:sort_direction] || 'asc'
      
      # Validate sort parameters to prevent SQL injection
      valid_sort_columns = ['id', 'name', 'position', 'house_account_balance', 'active', 'created_at']
      valid_sort_directions = ['asc', 'desc']
      
      sort_by = 'name' unless valid_sort_columns.include?(sort_by)
      sort_direction = 'asc' unless valid_sort_directions.include?(sort_direction)
      
      total_count = staff_members.count
      
      staff_members = staff_members.order("#{sort_by} #{sort_direction}")
                                  .offset((page - 1) * per_page)
                                  .limit(per_page)
      
      # Calculate total pages
      total_pages = (total_count.to_f / per_page).ceil
      
      {
        success: true,
        staff_members: staff_members,
        total_count: total_count,
        page: page,
        per_page: per_page,
        total_pages: total_pages
      }
    rescue => e
      { success: false, errors: ["Failed to retrieve staff members: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Get a specific staff member by ID
  def get_staff_member(id)
    begin
      staff_member = StaffMember.find_by(id: id, restaurant_id: current_restaurant.id)
      
      unless staff_member
        return { success: false, errors: ["Staff member not found"], status: :not_found }
      end
      
      { success: true, staff_member: staff_member }
    rescue => e
      { success: false, errors: ["Failed to retrieve staff member: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Create a new staff member
  def create_staff_member(staff_member_params, current_user)
    begin
      # Only admin users can create staff members
      unless current_user&.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Unauthorized"], status: :unauthorized }
      end
      
      # Ensure the staff member belongs to the current restaurant
      staff_member_params_with_restaurant = staff_member_params.merge(restaurant_id: current_restaurant.id)
      
      staff_member = StaffMember.new(staff_member_params_with_restaurant)
      
      if staff_member.save
        # Track staff member creation
        analytics.track("staff_member.created", { 
          staff_member_id: staff_member.id,
          restaurant_id: current_restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, staff_member: staff_member, status: :created }
      else
        { success: false, errors: staff_member.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to create staff member: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Update an existing staff member
  def update_staff_member(id, staff_member_params, current_user)
    begin
      # Only admin users can update staff members
      unless current_user&.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Unauthorized"], status: :unauthorized }
      end
      
      staff_member = StaffMember.find_by(id: id, restaurant_id: current_restaurant.id)
      
      unless staff_member
        return { success: false, errors: ["Staff member not found"], status: :not_found }
      end
      
      if staff_member.update(staff_member_params)
        # Track staff member update
        analytics.track("staff_member.updated", { 
          staff_member_id: staff_member.id,
          restaurant_id: current_restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, staff_member: staff_member }
      else
        { success: false, errors: staff_member.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to update staff member: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Delete a staff member
  def delete_staff_member(id, current_user)
    begin
      # Only admin users can delete staff members
      unless current_user&.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Unauthorized"], status: :unauthorized }
      end
      
      staff_member = StaffMember.find_by(id: id, restaurant_id: current_restaurant.id)
      
      unless staff_member
        return { success: false, errors: ["Staff member not found"], status: :not_found }
      end
      
      if staff_member.destroy
        # Track staff member deletion
        analytics.track("staff_member.deleted", { 
          staff_member_id: id,
          restaurant_id: current_restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, message: "Staff member deleted successfully" }
      else
        { success: false, errors: ["Failed to delete staff member"], status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to delete staff member: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Get transactions for a staff member
  def get_transactions(id, params)
    begin
      # Only admin users can view staff member transactions
      unless params[:current_user]&.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Unauthorized"], status: :unauthorized }
      end

      staff_member = StaffMember.find_by(id: id, restaurant_id: current_restaurant.id)
      
      unless staff_member
        return { success: false, errors: ["Staff member not found"], status: :not_found }
      end
      
      transactions = staff_member.house_account_transactions.recent
      
      # Filter by transaction type if provided
      if params[:transaction_type].present?
        transactions = transactions.where(transaction_type: params[:transaction_type])
      end
      
      # Filter by date range if provided
      if params[:date_from].present? && params[:date_to].present?
        date_from = Date.parse(params[:date_from]).beginning_of_day
        date_to = Date.parse(params[:date_to]).end_of_day
        transactions = transactions.where(created_at: date_from..date_to)
      end
      
      # Add pagination
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 20).to_i
      
      total_count = transactions.count
      
      transactions = transactions.offset((page - 1) * per_page).limit(per_page)
      
      # Calculate total pages
      total_pages = (total_count.to_f / per_page).ceil
      
      {
        success: true,
        transactions: transactions,
        total_count: total_count,
        page: page,
        per_page: per_page,
        total_pages: total_pages,
        staff_member: staff_member
      }
    rescue => e
      { success: false, errors: ["Failed to retrieve transactions: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Add a transaction to a staff member
  def add_transaction(id, transaction_params, current_user)
    begin
      # Only admin users can add transactions
      unless current_user&.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Unauthorized"], status: :unauthorized }
      end
      
      staff_member = StaffMember.find_by(id: id, restaurant_id: current_restaurant.id)
      
      unless staff_member
        return { success: false, errors: ["Staff member not found"], status: :not_found }
      end
      
      # Validate transaction parameters
      unless transaction_params[:amount].present? && transaction_params[:transaction_type].present?
        return { success: false, errors: ["Amount and transaction type are required"], status: :unprocessable_entity }
      end
      
      # Process the transaction based on type
      case transaction_params[:transaction_type]
      when 'payment'
        # For payments, amount should be positive but stored as negative
        amount = -transaction_params[:amount].to_f.abs
        description = "Payment - #{transaction_params[:description] || 'Manual payment'}"
        reference = transaction_params[:reference] || "Processed by #{current_user.full_name}"
      when 'adjustment'
        # For adjustments, amount can be positive or negative
        amount = transaction_params[:amount].to_f
        description = "Adjustment - #{transaction_params[:description] || 'Manual adjustment'}"
        reference = transaction_params[:reference] || "Processed by #{current_user.full_name}"
      when 'charge'
        # For charges, amount should be positive
        amount = transaction_params[:amount].to_f.abs
        description = "Charge - #{transaction_params[:description] || 'Manual charge'}"
        reference = transaction_params[:reference] || "Processed by #{current_user.full_name}"
      else
        return { success: false, errors: ["Invalid transaction type"], status: :unprocessable_entity }
      end
      
      # Create the transaction
      transaction = staff_member.house_account_transactions.new(
        amount: amount,
        transaction_type: transaction_params[:transaction_type],
        description: description,
        reference: reference,
        created_by_id: current_user.id
      )
      
      if transaction.save
        # Update the staff member's house account balance
        new_balance = staff_member.house_account_balance + amount
        staff_member.update(house_account_balance: new_balance)
        
        # Track transaction creation
        analytics.track("staff_member.transaction_added", { 
          staff_member_id: staff_member.id,
          transaction_id: transaction.id,
          amount: transaction.amount,
          restaurant_id: current_restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, transaction: transaction, staff_member: staff_member, status: :created }
      else
        { success: false, errors: transaction.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to add transaction: #{e.message}"], status: :internal_server_error }
    end
  end
end
