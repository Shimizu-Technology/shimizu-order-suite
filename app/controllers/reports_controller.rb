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
                   .includes(:staff_member, :staff_discount_configuration)
    
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
    
    # Enhance orders with discount_type information and configuration details
    orders_with_discount_type = @orders.map do |order|
      # Get discount configuration and information
      discount_config = order.staff_discount_configuration
      discount_config_name = nil
      discount_config_percentage = nil
      discount_config_type = nil
      
      # Get discount type from payment_details, with fallback to staff_on_duty
      discount_type = order.get_discount_type_from_params || 
                     (order.staff_on_duty? ? 'on_duty' : 'off_duty')
      
      # Calculate discount rate and amount
      if discount_config.present?
        # Use the actual configuration
        discount_rate = discount_config.discount_rate
        discount_config_name = discount_config.name
        discount_config_percentage = discount_config.discount_percentage
        discount_config_type = discount_config.discount_type
      else
        # Fallback to hardcoded values for backward compatibility
        discount_rate = case discount_type
                       when 'on_duty' then 0.5  # 50%
                       when 'off_duty' then 0.3  # 30%
                       when 'no_discount' then 0.0  # 0%
                       else 0.3  # fallback to 30%
                       end
      end
      
      # Add additional computed fields for the frontend
      order_hash = order.as_json
      order_hash['discount_type'] = discount_type
      order_hash['discount_rate'] = discount_rate
      order_hash['discount_amount'] = (order.pre_discount_total || order.total) * discount_rate
      order_hash['discount_percentage'] = (discount_rate * 100).to_i
      
      # Add staff discount configuration information
      order_hash['staff_discount_configuration'] = if discount_config.present?
        {
          id: discount_config.id,
          name: discount_config.name,
          code: discount_config.code,
          discount_percentage: discount_config.discount_percentage,
          discount_type: discount_config.discount_type,
          display_label: discount_config.display_label
        }
      else
        nil
      end
      
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
    
    # Get all staff orders in the date range with discount configurations
    staff_orders = Order.where(is_staff_order: true, created_at: date_range)
                        .includes(:staff_discount_configuration)
    
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
    
    # Calculate breakdown by discount configuration (new approach)
    discount_breakdown = {}
    
    # Also maintain backward compatibility with legacy breakdown
    on_duty_retail = 0
    on_duty_discounted = 0
    off_duty_retail = 0
    off_duty_discounted = 0
    no_discount_retail = 0
    no_discount_discounted = 0
    
    staff_orders.each do |order|
      # Get pre-discount total
      pre_discount = 0
      if order.payment_details && order.payment_details['staffOrderParams'] && 
         order.payment_details['staffOrderParams']['pre_discount_total'].present?
        pre_discount = order.payment_details['staffOrderParams']['pre_discount_total'].to_f
      end
      
      # Handle configurable discounts
      if order.staff_discount_configuration.present?
        config = order.staff_discount_configuration
        config_key = config.code
        
        # Initialize breakdown for this configuration if not exists
        unless discount_breakdown[config_key]
          discount_breakdown[config_key] = {
            configuration_id: config.id,
            configuration_name: config.name,
            configuration_code: config.code,
            discount_percentage: config.discount_percentage,
            discount_type: config.discount_type,
            order_count: 0,
            retail_value: 0,
            discounted_value: 0,
            discount_amount: 0,
            discount_percentage_actual: 0
          }
        end
        
        # Add to configuration breakdown
        discount_breakdown[config_key][:order_count] += 1
        discount_breakdown[config_key][:retail_value] += pre_discount
        discount_breakdown[config_key][:discounted_value] += order.total
        discount_breakdown[config_key][:discount_amount] += (pre_discount - order.total)
        
        # Also add to legacy breakdown for backward compatibility
        case config.code
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
          # Custom discount configurations - add to off_duty for legacy compatibility
          off_duty_retail += pre_discount
          off_duty_discounted += order.total
        end
      else
        # Fallback for orders without discount configuration
        discount_type = order.get_discount_type_from_params || 
                       (order.staff_on_duty? ? 'on_duty' : 'off_duty')
        
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
    end
    
    # Calculate percentage for each discount configuration
    discount_breakdown.each do |key, breakdown|
      if breakdown[:retail_value] > 0
        breakdown[:discount_percentage_actual] = (breakdown[:discount_amount] / breakdown[:retail_value] * 100).round(2)
      end
    end
    
    on_duty_discount = on_duty_retail - on_duty_discounted
    off_duty_discount = off_duty_retail - off_duty_discounted
    no_discount_discount = no_discount_retail - no_discount_discounted
    
    # Calculate breakdown by staff member (with new discount configurations)
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
      
      # Track discount configurations used by this staff member
      member_discount_breakdown = {}
      
      member_orders.each do |order|
        # Get pre-discount total
        pre_discount = 0
        if order.payment_details && order.payment_details['staffOrderParams'] && 
           order.payment_details['staffOrderParams']['pre_discount_total'].present?
          pre_discount = order.payment_details['staffOrderParams']['pre_discount_total'].to_f
        end
        
        # Handle configurable discounts
        if order.staff_discount_configuration.present?
          config = order.staff_discount_configuration
          config_key = config.code
          
          # Initialize breakdown for this configuration if not exists
          unless member_discount_breakdown[config_key]
            member_discount_breakdown[config_key] = {
              configuration_name: config.name,
              configuration_code: config.code,
              order_count: 0,
              retail_value: 0,
              discounted_value: 0,
              discount_amount: 0
            }
          end
          
          # Add to member's configuration breakdown
          member_discount_breakdown[config_key][:order_count] += 1
          member_discount_breakdown[config_key][:retail_value] += pre_discount
          member_discount_breakdown[config_key][:discounted_value] += order.total
          member_discount_breakdown[config_key][:discount_amount] += (pre_discount - order.total)
          
          # Also add to legacy breakdown for backward compatibility
          case config.code
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
            # Custom discount configurations - add to off_duty for legacy compatibility
            member_off_duty_retail += pre_discount
            member_off_duty_discounted += order.total
            member_off_duty_count += 1
          end
        else
          # Fallback for orders without discount configuration
          discount_type = order.get_discount_type_from_params || 
                         (order.staff_on_duty? ? 'on_duty' : 'off_duty')
          
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
        total_discount: member_on_duty_discount + member_off_duty_discount + member_no_discount_discount,
        discount_configurations: member_discount_breakdown.values
      }
    end
    
    # Count orders by discount type for the breakdown
    on_duty_count = staff_orders.count { |order| 
      if order.staff_discount_configuration.present?
        order.staff_discount_configuration.code == 'on_duty'
      else
        discount_type = order.get_discount_type_from_params || 
                       (order.staff_on_duty? ? 'on_duty' : 'off_duty')
        discount_type == 'on_duty'
      end
    }
    
    off_duty_count = staff_orders.count { |order| 
      if order.staff_discount_configuration.present?
        order.staff_discount_configuration.code == 'off_duty'
      else
        discount_type = order.get_discount_type_from_params || 
                       (order.staff_on_duty? ? 'on_duty' : 'off_duty')
        discount_type == 'off_duty'
      end
    }
    
    no_discount_count = staff_orders.count { |order| 
      if order.staff_discount_configuration.present?
        order.staff_discount_configuration.code == 'no_discount'
      else
        discount_type = order.get_discount_type_from_params || 
                       (order.staff_on_duty? ? 'on_duty' : 'off_duty')
        discount_type == 'no_discount'
      end
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
      # New discount configuration breakdown
      discount_configurations: discount_breakdown.values,
      # Legacy breakdown for backward compatibility
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
    
    # Get all transactions for this staff member with order associations
    @transactions = @staff_member.house_account_transactions
                                 .includes(:order => :staff_discount_configuration)
                                 .order(created_at: :desc)
    
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
    
    # Enhanced transaction data with order details
    enhanced_transactions = @transactions.map do |transaction|
      transaction_data = transaction.as_json
      
      # Add order details if this transaction is related to an order
      if transaction.order.present?
        order = transaction.order
        
        # Get discount information
        discount_info = if order.staff_discount_configuration.present?
          config = order.staff_discount_configuration
          {
            discount_name: config.name,
            discount_type: config.discount_type,
            discount_percentage: config.discount_percentage,
            discount_code: config.code,
            discount_amount: (order.pre_discount_total || 0) - order.total,
            pre_discount_total: order.pre_discount_total || 0
          }
        elsif order.is_staff_order?
          # Fallback for orders without discount configuration
          discount_type = order.get_discount_type_from_params || 
                         (order.staff_on_duty? ? 'on_duty' : 'off_duty')
          discount_rate = case discount_type
                         when 'on_duty' then 0.5
                         when 'off_duty' then 0.3
                         when 'no_discount' then 0.0
                         else 0.3
                         end
          
          pre_discount = order.pre_discount_total || order.total / (1 - discount_rate)
          
          {
            discount_name: discount_type.humanize,
            discount_type: 'percentage',
            discount_percentage: (discount_rate * 100).to_i,
            discount_code: discount_type,
            discount_amount: pre_discount - order.total,
            pre_discount_total: pre_discount
          }
        else
          nil
        end
        
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
    
    render json: {
      staff_member: @staff_member,
      transactions: enhanced_transactions,
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
