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
      # Parse with timezone consideration
      date_from = Time.zone.parse(params[:date_from]).beginning_of_day
      date_to = Time.zone.parse(params[:date_to]).end_of_day
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
    
    # Enhance orders with discount_type information
    orders_with_discount_type = @orders.map do |order|
      # Get discount type from payment_details, with fallback to staff_on_duty
      discount_type = order.get_discount_type_from_params || 
                     (order.staff_on_duty? ? 'on_duty' : 'off_duty')
      
      # Add additional computed fields for the frontend
      order_hash = order.as_json
      order_hash['discount_type'] = discount_type
      order_hash['discount_rate'] = case discount_type
                                   when 'on_duty' then 0.5  # 50%
                                   when 'off_duty' then 0.3  # 30%
                                   when 'no_discount' then 0.0  # 0%
                                   else 0.3  # fallback to 30%
                                   end
      order_hash['discount_amount'] = (order.pre_discount_total || order.total) * order_hash['discount_rate']
      order_hash['discount_percentage'] = (order_hash['discount_rate'] * 100).to_i
      
      # Add staff member name if available
      if order.staff_member
        order_hash['staff_member_name'] = order.staff_member.name
      end
      
      order_hash
    end

    render json: {
      orders: orders_with_discount_type,
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
      # Parse with timezone consideration
      date_from = Time.zone.parse(params[:date_from]).beginning_of_day
      date_to = Time.zone.parse(params[:date_to]).end_of_day
      date_range = date_from..date_to
    else
      # Default to current month in Guam timezone
      date_range = Time.zone.now.beginning_of_month..Time.zone.now.end_of_month
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
    
    # Calculate breakdown by discount type (with backward compatibility)
    on_duty_retail = 0
    on_duty_discounted = 0
    off_duty_retail = 0
    off_duty_discounted = 0
    no_discount_retail = 0
    no_discount_discounted = 0
    
    staff_orders.each do |order|
      # Get discount type from payment_details, with fallback to staff_on_duty
      discount_type = order.get_discount_type_from_params || 
                     (order.staff_on_duty? ? 'on_duty' : 'off_duty')
      
      # Get pre-discount total
      pre_discount = 0
      if order.payment_details && order.payment_details['staffOrderParams'] && 
         order.payment_details['staffOrderParams']['pre_discount_total'].present?
        pre_discount = order.payment_details['staffOrderParams']['pre_discount_total'].to_f
      end
      
      case discount_type
      when 'on_duty'
        on_duty_retail += pre_discount
        on_duty_discounted += order.total
      when 'off_duty'
        off_duty_retail += pre_discount
        off_duty_discounted += order.total
      when 'no_discount'
        no_discount_retail += pre_discount
        no_discount_discounted += order.total
      else
        # Default fallback to off_duty for unknown types
        off_duty_retail += pre_discount
        off_duty_discounted += order.total
      end
    end
    
    on_duty_discount = on_duty_retail - on_duty_discounted
    off_duty_discount = off_duty_retail - off_duty_discounted
    no_discount_discount = no_discount_retail - no_discount_discounted
    
          # Calculate breakdown by staff member (with new discount types)
      by_staff_member = []
      
      staff_members = StaffMember.where(id: staff_orders.pluck(:staff_member_id).uniq)
      staff_members.each do |staff|
        member_orders = staff_orders.where(staff_member_id: staff.id)
        
        # Initialize counters for this staff member
        member_on_duty_retail = 0
        member_on_duty_discounted = 0
        member_off_duty_retail = 0
        member_off_duty_discounted = 0
        member_no_discount_retail = 0
        member_no_discount_discounted = 0
        
        member_on_duty_count = 0
        member_off_duty_count = 0
        member_no_discount_count = 0
        
        member_orders.each do |order|
          # Get discount type from payment_details, with fallback to staff_on_duty
          discount_type = order.get_discount_type_from_params || 
                         (order.staff_on_duty? ? 'on_duty' : 'off_duty')
          
          # Get pre-discount total
          pre_discount = 0
          if order.payment_details && order.payment_details['staffOrderParams'] && 
             order.payment_details['staffOrderParams']['pre_discount_total'].present?
            pre_discount = order.payment_details['staffOrderParams']['pre_discount_total'].to_f
          end
          
          case discount_type
          when 'on_duty'
            member_on_duty_retail += pre_discount
            member_on_duty_discounted += order.total
            member_on_duty_count += 1
          when 'off_duty'
            member_off_duty_retail += pre_discount
            member_off_duty_discounted += order.total
            member_off_duty_count += 1
          when 'no_discount'
            member_no_discount_retail += pre_discount
            member_no_discount_discounted += order.total
            member_no_discount_count += 1
          else
            # Default fallback to off_duty
            member_off_duty_retail += pre_discount
            member_off_duty_discounted += order.total
            member_off_duty_count += 1
          end
        end
        
        member_on_duty_discount = member_on_duty_retail - member_on_duty_discounted
        member_off_duty_discount = member_off_duty_retail - member_off_duty_discounted
        member_no_discount_discount = member_no_discount_retail - member_no_discount_discounted
        
        # Add to staff breakdown with the new format
        by_staff_member << {
          staff_id: staff.id,
          staff_name: staff.name,
          on_duty_count: member_on_duty_count,
          off_duty_count: member_off_duty_count,
          no_discount_count: member_no_discount_count,
          on_duty_discount: member_on_duty_discount,
          off_duty_discount: member_off_duty_discount,
          no_discount_discount: member_no_discount_discount,
          total_discount: member_on_duty_discount + member_off_duty_discount + member_no_discount_discount
        }
      end
    
    # Count orders by discount type for the breakdown
    on_duty_count = staff_orders.count { |order| 
      discount_type = order.get_discount_type_from_params || 
                     (order.staff_on_duty? ? 'on_duty' : 'off_duty')
      discount_type == 'on_duty'
    }
    
    off_duty_count = staff_orders.count { |order| 
      discount_type = order.get_discount_type_from_params || 
                     (order.staff_on_duty? ? 'on_duty' : 'off_duty')
      discount_type == 'off_duty'
    }
    
    no_discount_count = staff_orders.count { |order| 
      discount_type = order.get_discount_type_from_params || 
                     (order.staff_on_duty? ? 'on_duty' : 'off_duty')
      discount_type == 'no_discount'
    }

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
          order_count: on_duty_count,
          retail_value: on_duty_retail,
          discounted_value: on_duty_discounted,
          discount_amount: on_duty_discount,
          discount_percentage: on_duty_retail > 0 ? (on_duty_discount / on_duty_retail * 100).round(2) : 0
        },
        off_duty: {
          order_count: off_duty_count,
          retail_value: off_duty_retail,
          discounted_value: off_duty_discounted,
          discount_amount: off_duty_discount,
          discount_percentage: off_duty_retail > 0 ? (off_duty_discount / off_duty_retail * 100).round(2) : 0
        },
        no_discount: {
          order_count: no_discount_count,
          retail_value: no_discount_retail,
          discounted_value: no_discount_discounted,
          discount_amount: no_discount_discount,
          discount_percentage: no_discount_retail > 0 ? (no_discount_discount / no_discount_retail * 100).round(2) : 0
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
