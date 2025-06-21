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
  def get_transactions(staff_member_id, options = {})
    begin
      staff_member = StaffMember.find_by(id: staff_member_id, restaurant_id: current_restaurant.id)
      
      unless staff_member
        return { success: false, errors: ["Staff member not found"], status: :not_found }
      end
      
      # Build the base query with order associations for discount information
      query = staff_member.house_account_transactions
                          .includes(:order => :staff_discount_configuration)
      
      # Apply date filtering (specify table name to avoid ambiguity)
      if options[:start_date].present?
        begin
          start_date = Date.parse(options[:start_date]).beginning_of_day
          query = query.where('house_account_transactions.created_at >= ?', start_date)
        rescue ArgumentError
          return { success: false, errors: ["Invalid start date format"], status: :bad_request }
        end
      end
      
      if options[:end_date].present?
        begin
          end_date = Date.parse(options[:end_date]).end_of_day
          query = query.where('house_account_transactions.created_at <= ?', end_date)
        rescue ArgumentError
          return { success: false, errors: ["Invalid end date format"], status: :bad_request }
        end
      end
      
      # Apply transaction type filtering
      if options[:transaction_type].present? && options[:transaction_type] != 'all'
        query = query.where(transaction_type: options[:transaction_type])
      end
      
      # Calculate statistics for the filtered results
      total_count = query.count
      order_total = query.where(transaction_type: ['order', 'charge']).sum(:amount)
      payment_total = query.where(transaction_type: 'payment').sum('ABS(amount)')
      period_total = query.sum(:amount)
      
      # Apply pagination
      page = [options[:page].to_i, 1].max
      per_page = [options[:per_page].to_i, 20].max
      per_page = [per_page, 100].min # Cap at 100 per page
      
      offset = (page - 1) * per_page
      transactions = query.order(created_at: :desc)
                          .limit(per_page)
                          .offset(offset)
      
      # Enhanced transaction formatting with order details
      formatted_transactions = transactions.map do |transaction|
        transaction_data = {
          id: transaction.id,
          amount: transaction.amount.to_f,
          transaction_type: transaction.transaction_type,
          description: transaction.description,
          reference: transaction.reference,
          created_at: transaction.created_at,
          created_by_name: transaction.created_by&.full_name || 'System'
        }
        
        # Add order details for order transactions
        if transaction.transaction_type == 'order' && transaction.order.present?
          order = transaction.order
          
          # Build discount information
          discount_info = if order.staff_discount_configuration.present?
            # Use configurable discount information
            config = order.staff_discount_configuration
            {
              discount_name: config.name,
              discount_type: config.discount_type,
              discount_percentage: config.discount_percentage,
              discount_code: config.code,
              discount_amount: (order.pre_discount_total || order.total) - order.total,
              pre_discount_total: order.pre_discount_total || order.total
            }
          elsif order.is_staff_order?
            # Fallback to legacy discount calculation
            discount_rate = order.staff_on_duty? ? 0.5 : 0.3
            discount_name = order.staff_on_duty? ? 'On Duty Staff' : 'Off Duty Staff'
            discount_code = order.staff_on_duty? ? 'on_duty' : 'off_duty'
            pre_discount_total = order.pre_discount_total || (order.total / (1 - discount_rate))
            
            {
              discount_name: discount_name,
              discount_type: 'percentage',
              discount_percentage: (discount_rate * 100).to_i,
              discount_code: discount_code,
              discount_amount: pre_discount_total - order.total,
              pre_discount_total: pre_discount_total
            }
          else
            nil
          end
          
          # Add order details to transaction data
          transaction_data.merge!({
            order_details: {
              order_id: order.id,
              order_number: order.order_number || order.id.to_s,
              is_staff_order: order.is_staff_order?,
              staff_on_duty: order.staff_on_duty?,
              total: order.total,
              discount_info: discount_info
            }
          })
        end
        
        transaction_data
      end
      
      { 
        success: true, 
        transactions: formatted_transactions,
        pagination: {
          page: page,
          per_page: per_page,
          total_count: total_count,
          total_pages: (total_count.to_f / per_page).ceil
        },
        statistics: {
          total_count: total_count,
          filtered_count: total_count,
          period_total: period_total.to_f,
          order_total: order_total.to_f,
          payment_total: payment_total.to_f
        }
      }
    rescue => e
      Rails.logger.error "Error getting staff member transactions: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { success: false, errors: ["Unable to retrieve transactions"], status: :internal_server_error }
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
      
      # Create transaction using the staff member model method
      transaction = staff_member.add_house_account_transaction(
        transaction_params[:amount],
        transaction_params[:transaction_type],
        transaction_params[:description],
        nil, # order
        current_user
      )
      
      # Track transaction creation
      analytics.track("house_account_transaction.created", { 
        staff_member_id: staff_member.id,
        transaction_id: transaction.id,
        amount: transaction_params[:amount],
        transaction_type: transaction_params[:transaction_type],
        restaurant_id: current_restaurant.id,
        user_id: current_user.id
      })
      
      { success: true, transaction: transaction }
    rescue => e
      { success: false, errors: ["Failed to add transaction: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Link a user to a staff member
  def link_user(staff_id, user_id, current_user)
    begin
      # Only admin users can link users
      unless current_user&.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Unauthorized"], status: :unauthorized }
      end
      
      staff_member = StaffMember.find_by(id: staff_id, restaurant_id: current_restaurant.id)
      unless staff_member
        return { success: false, errors: ["Staff member not found"], status: :not_found }
      end
      
      user = User.find_by(id: user_id, restaurant_id: current_restaurant.id)
      unless user
        return { success: false, errors: ["User not found"], status: :not_found }
      end
      
      # Check if user is already linked to another staff member
      existing_staff = StaffMember.find_by(user_id: user_id, restaurant_id: current_restaurant.id)
      if existing_staff && existing_staff.id != staff_member.id
        return { success: false, errors: ["User is already linked to another staff member: #{existing_staff.name}"], status: :unprocessable_entity }
      end
      
      # Check if staff member is already linked to another user
      if staff_member.user_id.present? && staff_member.user_id != user_id.to_i
        current_user_name = User.find_by(id: staff_member.user_id)&.full_name || "Unknown User"
        return { success: false, errors: ["Staff member is already linked to another user: #{current_user_name}"], status: :unprocessable_entity }
      end
      
      # Link the user to the staff member
      if staff_member.update(user_id: user_id)
        # Track user linking
        analytics.track("staff_member.user_linked", { 
          staff_member_id: staff_member.id,
          user_id: user_id,
          restaurant_id: current_restaurant.id,
          linked_by_user_id: current_user.id
        })
        
        { success: true, staff_member: staff_member.reload }
      else
        { success: false, errors: staff_member.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to link user: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Unlink a user from a staff member
  def unlink_user(staff_id, current_user)
    begin
      # Only admin users can unlink users
      unless current_user&.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Unauthorized"], status: :unauthorized }
      end
      
      staff_member = StaffMember.find_by(id: staff_id, restaurant_id: current_restaurant.id)
      unless staff_member
        return { success: false, errors: ["Staff member not found"], status: :not_found }
      end
      
      # Check if staff member has a user linked
      unless staff_member.user_id.present?
        return { success: false, errors: ["Staff member is not linked to any user"], status: :unprocessable_entity }
      end
      
      # Store the user_id for analytics before unlinking
      unlinked_user_id = staff_member.user_id
      
      # Unlink the user from the staff member
      if staff_member.update(user_id: nil)
        # Track user unlinking
        analytics.track("staff_member.user_unlinked", { 
          staff_member_id: staff_member.id,
          unlinked_user_id: unlinked_user_id,
          restaurant_id: current_restaurant.id,
          unlinked_by_user_id: current_user.id
        })
        
        { success: true, staff_member: staff_member.reload }
      else
        { success: false, errors: staff_member.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to unlink user: #{e.message}"], status: :internal_server_error }
    end
  end
end
