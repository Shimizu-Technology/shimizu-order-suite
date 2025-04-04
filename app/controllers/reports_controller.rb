class ReportsController < ApplicationController
  before_action :authorize_request
  
  # Override public_endpoint? to allow staff-related reports without restaurant context
  def public_endpoint?
    %w[staff_orders house_account_balances discount_summary house_account_activity].include?(action_name)
  end
  
  # GET /reports/house_account_balances
  def house_account_balances
    # Only admin users can access reports
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end
    
    # Get all staff members with house account balances
    @staff_members = StaffMember.where('house_account_balance > 0').order(house_account_balance: :desc)
    
    # Calculate totals
    total_balance = @staff_members.sum(:house_account_balance)
    
    render json: {
      staff_members: @staff_members,
      total_balance: total_balance,
      count: @staff_members.count
    }, status: :ok
  end
  
  # GET /reports/staff_orders
  def staff_orders
    # Only admin users can access reports
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end
    
    # Get all staff orders with optional filtering
    @orders = Order.where(is_staff_order: true)
    
    # Filter by staff member if provided
    if params[:staff_member_id].present?
      @orders = @orders.where(staff_member_id: params[:staff_member_id])
    end
    
    # Filter by duty status if provided
    if params[:staff_on_duty].present?
      @orders = @orders.where(staff_on_duty: params[:staff_on_duty] == 'true')
    end
    
    # Filter by house account usage if provided
    if params[:use_house_account].present?
      @orders = @orders.where(use_house_account: params[:use_house_account] == 'true')
    end
    
    # Filter by date range if provided
    if params[:date_from].present? && params[:date_to].present?
      date_from = Date.parse(params[:date_from]).beginning_of_day
      date_to = Date.parse(params[:date_to]).end_of_day
      @orders = @orders.where(created_at: date_from..date_to)
    end
    
    # Add pagination
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i
    
    # Apply sorting
    sort_by = params[:sort_by] || 'created_at'
    sort_direction = params[:sort_direction] || 'desc'
    
    # Validate sort parameters to prevent SQL injection
    valid_sort_columns = ['id', 'created_at', 'staff_member_id', 'total', 'pre_discount_total']
    valid_sort_directions = ['asc', 'desc']
    
    sort_by = 'created_at' unless valid_sort_columns.include?(sort_by)
    sort_direction = 'desc' unless valid_sort_directions.include?(sort_direction)
    
    total_count = @orders.count
    
    @orders = @orders.order("#{sort_by} #{sort_direction}")
                     .offset((page - 1) * per_page)
                     .limit(per_page)
    
    # Calculate totals
    total_pre_discount = Order.where(is_staff_order: true).sum(:pre_discount_total)
    total_after_discount = Order.where(is_staff_order: true).sum(:total)
    total_discount = total_pre_discount - total_after_discount
    
    # Calculate total pages
    total_pages = (total_count.to_f / per_page).ceil
    
    render json: {
      orders: @orders,
      total_count: total_count,
      page: page,
      per_page: per_page,
      total_pages: total_pages,
      total_pre_discount: total_pre_discount,
      total_after_discount: total_after_discount,
      total_discount: total_discount
    }, status: :ok
  end
  
  # GET /reports/discount_summary
  def discount_summary
    # Only admin users can access reports
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end
    
    # Filter by date range if provided
    if params[:date_from].present? && params[:date_to].present?
      date_from = Date.parse(params[:date_from]).beginning_of_day
      date_to = Date.parse(params[:date_to]).end_of_day
      date_range = date_from..date_to
    else
      # Default to current month
      date_range = Time.current.beginning_of_month..Time.current.end_of_month
    end
    
    # Get all staff orders in the date range
    staff_orders = Order.where(is_staff_order: true, created_at: date_range)
    
    # Calculate totals
    total_retail_value = 0
    total_discounted_value = 0
    
    # For each order, calculate the pre-discount total from payment_details if available
    staff_orders.each do |order|
      # Get pre_discount_total from payment_details if available
      if order.payment_details && order.payment_details['staffOrderParams'] && 
         order.payment_details['staffOrderParams']['pre_discount_total'].present?
        pre_discount = order.payment_details['staffOrderParams']['pre_discount_total'].to_f
        total_retail_value += pre_discount
      end
      total_discounted_value += order.total
    end
    
    total_discount_amount = total_retail_value - total_discounted_value
    
    # Calculate breakdown by duty status
    on_duty_orders = staff_orders.where(staff_on_duty: true)
    off_duty_orders = staff_orders.where(staff_on_duty: false)
    
    on_duty_retail = 0
    on_duty_discounted = 0
    
    on_duty_orders.each do |order|
      if order.payment_details && order.payment_details['staffOrderParams'] && 
         order.payment_details['staffOrderParams']['pre_discount_total'].present?
        on_duty_retail += order.payment_details['staffOrderParams']['pre_discount_total'].to_f
      end
      on_duty_discounted += order.total
    end
    
    on_duty_discount = on_duty_retail - on_duty_discounted
    
    off_duty_retail = 0
    off_duty_discounted = 0
    
    off_duty_orders.each do |order|
      if order.payment_details && order.payment_details['staffOrderParams'] && 
         order.payment_details['staffOrderParams']['pre_discount_total'].present?
        off_duty_retail += order.payment_details['staffOrderParams']['pre_discount_total'].to_f
      end
      off_duty_discounted += order.total
    end
    
    off_duty_discount = off_duty_retail - off_duty_discounted
    
    # Calculate breakdown by staff member
    by_staff_member = []
    
    staff_members = StaffMember.where(id: staff_orders.pluck(:staff_member_id).uniq)
    staff_members.each do |staff|
      member_orders = staff_orders.where(staff_member_id: staff.id)
      member_on_duty = member_orders.where(staff_on_duty: true)
      member_off_duty = member_orders.where(staff_on_duty: false)
      
      # Calculate on-duty metrics
      on_duty_retail = 0
      on_duty_discounted = 0
      
      member_on_duty.each do |order|
        if order.payment_details && order.payment_details['staffOrderParams'] && 
           order.payment_details['staffOrderParams']['pre_discount_total'].present?
          on_duty_retail += order.payment_details['staffOrderParams']['pre_discount_total'].to_f
        end
        on_duty_discounted += order.total
      end
      
      on_duty_discount = on_duty_retail - on_duty_discounted
      
      # Calculate off-duty metrics
      off_duty_retail = 0
      off_duty_discounted = 0
      
      member_off_duty.each do |order|
        if order.payment_details && order.payment_details['staffOrderParams'] && 
           order.payment_details['staffOrderParams']['pre_discount_total'].present?
          off_duty_retail += order.payment_details['staffOrderParams']['pre_discount_total'].to_f
        end
        off_duty_discounted += order.total
      end
      
      off_duty_discount = off_duty_retail - off_duty_discounted
      
      # Add to staff breakdown with the exact format expected by the frontend
      by_staff_member << {
        staff_id: staff.id,
        staff_name: staff.name,
        on_duty_count: member_on_duty.count,
        off_duty_count: member_off_duty.count,
        on_duty_discount: on_duty_discount,
        off_duty_discount: off_duty_discount,
        total_discount: on_duty_discount + off_duty_discount
      }
    end
    
    render json: {
      date_range: {
        from: date_range.begin,
        to: date_range.end
      },
      total_orders: staff_orders.count,
      total_retail_value: total_retail_value,
      total_discounted_value: total_discounted_value,
      total_discount_amount: total_discount_amount,
      discount_percentage: total_retail_value > 0 ? (total_discount_amount / total_retail_value * 100).round(2) : 0,
      duty_breakdown: {
        on_duty: {
          order_count: on_duty_orders.count,
          retail_value: on_duty_retail,
          discounted_value: on_duty_discounted,
          discount_amount: on_duty_discount,
          discount_percentage: on_duty_retail > 0 ? (on_duty_discount / on_duty_retail * 100).round(2) : 0
        },
        off_duty: {
          order_count: off_duty_orders.count,
          retail_value: off_duty_retail,
          discounted_value: off_duty_discounted,
          discount_amount: off_duty_discount,
          discount_percentage: off_duty_retail > 0 ? (off_duty_discount / off_duty_retail * 100).round(2) : 0
        }
      },
      by_staff_member: by_staff_member
    }, status: :ok
  end
  
  # GET /reports/house_account_activity/:staff_id
  def house_account_activity
    # Only admin users can access reports
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end
    
    # Find the staff member
    @staff_member = StaffMember.find(params[:staff_id])
    
    # Get all transactions for this staff member
    @transactions = @staff_member.house_account_transactions.order(created_at: :desc)
    
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
    
    # Calculate totals by transaction type
    order_charges = @transactions.where(transaction_type: 'order').sum(:amount)
    payments = @transactions.where(transaction_type: 'payment').sum(:amount).abs
    adjustments = @transactions.where(transaction_type: 'adjustment').sum(:amount)
    
    @transactions = @transactions.offset((page - 1) * per_page).limit(per_page)
    
    # Calculate total pages
    total_pages = (total_count.to_f / per_page).ceil
    
    render json: {
      staff_member: @staff_member,
      transactions: @transactions,
      total_count: total_count,
      page: page,
      per_page: per_page,
      total_pages: total_pages,
      summary: {
        current_balance: @staff_member.house_account_balance,
        total_charges: order_charges,
        total_payments: payments,
        total_adjustments: adjustments
      }
    }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Staff member not found" }, status: :not_found
  end
end
