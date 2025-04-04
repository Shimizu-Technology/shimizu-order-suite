class StaffMembersController < ApplicationController
  before_action :authorize_request
  before_action :set_staff_member, only: [:show, :update, :destroy, :transactions, :add_transaction]
  
  # Override public_endpoint? to make staff_members a public endpoint
  def public_endpoint?
    action_name.in?(["index", "create", "update", "show", "destroy", "transactions", "add_transaction"])
  end
  
  # GET /staff_members
  def index
    # Only admin users can access staff members
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end
    
    @staff_members = StaffMember.all
    
    # Filter by user_id if provided
    if params[:user_id].present?
      @staff_members = @staff_members.where(user_id: params[:user_id])
    end
    
    # Filter by active status if provided
    if params[:active].present?
      @staff_members = @staff_members.where(active: params[:active] == 'true')
    end
    
    # Filter by house account balance if provided
    if params[:with_balance].present? && params[:with_balance] == 'true'
      @staff_members = @staff_members.with_house_account_balance
    end
    
    # Search functionality
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @staff_members = @staff_members.where(
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
    
    total_count = @staff_members.count
    
    @staff_members = @staff_members.order("#{sort_by} #{sort_direction}")
                                  .offset((page - 1) * per_page)
                                  .limit(per_page)
    
    # Calculate total pages
    total_pages = (total_count.to_f / per_page).ceil
    
    render json: {
      staff_members: @staff_members,
      total_count: total_count,
      page: page,
      per_page: per_page,
      total_pages: total_pages
    }, status: :ok
  end
  
  # GET /staff_members/:id
  def show
    render json: @staff_member
  end
  
  # POST /staff_members
  def create
    # Only admin users can create staff members
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end
    
    @staff_member = StaffMember.new(staff_member_params)
    
    if @staff_member.save
      render json: @staff_member, status: :created
    else
      render json: { errors: @staff_member.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  # PATCH/PUT /staff_members/:id
  def update
    # Only admin users can update staff members
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end
    
    if @staff_member.update(staff_member_params)
      render json: @staff_member
    else
      render json: { errors: @staff_member.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  # DELETE /staff_members/:id
  def destroy
    # Only admin users can delete staff members
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end
    
    @staff_member.destroy
    head :no_content
  end
  
  # GET /staff_members/:id/transactions
  def transactions
    # Only admin users can view staff member transactions
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end
    
    @transactions = @staff_member.house_account_transactions.recent
    
    # Filter by transaction type if provided
    if params[:transaction_type].present?
      @transactions = @transactions.where(transaction_type: params[:transaction_type])
    end
    
    # Filter by date range if provided
    if params[:date_from].present? && params[:date_to].present?
      date_from = Date.parse(params[:date_from]).beginning_of_day
      date_to = Date.parse(params[:date_to]).end_of_day
      @transactions = @transactions.where(created_at: date_from..date_to)
    end
    
    # Add pagination
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i
    
    total_count = @transactions.count
    
    @transactions = @transactions.offset((page - 1) * per_page).limit(per_page)
    
    # Calculate total pages
    total_pages = (total_count.to_f / per_page).ceil
    
    render json: {
      transactions: @transactions,
      total_count: total_count,
      page: page,
      per_page: per_page,
      total_pages: total_pages,
      staff_member: @staff_member
    }, status: :ok
  end
  
  # POST /staff_members/:id/transactions
  def add_transaction
    # Only admin users can add transactions
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end
    
    # Validate transaction parameters
    unless transaction_params[:amount].present? && transaction_params[:transaction_type].present?
      return render json: { error: "Amount and transaction type are required" }, status: :unprocessable_entity
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
      return render json: { error: "Invalid transaction type" }, status: :unprocessable_entity
    end
    
    # Create the transaction
    transaction = @staff_member.house_account_transactions.new(
      amount: amount,
      transaction_type: transaction_params[:transaction_type],
      description: description,
      reference: reference,
      created_by_id: current_user.id
    )
    
    if transaction.save
      # Update the staff member's house account balance
      new_balance = @staff_member.house_account_balance + amount
      @staff_member.update(house_account_balance: new_balance)
      
      render json: transaction, status: :created
    else
      render json: { errors: transaction.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  private
  
  def set_staff_member
    @staff_member = StaffMember.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Staff member not found" }, status: :not_found
  end
  
  def staff_member_params
    params.require(:staff_member).permit(:name, :position, :user_id, :active)
  end
  
  def transaction_params
    params.require(:transaction).permit(:amount, :transaction_type, :description, :reference)
  end
end
