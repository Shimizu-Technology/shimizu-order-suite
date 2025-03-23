class StaffDiscountsController < ApplicationController
  before_action :authorize_request
  before_action :authorize_admin, except: [:index, :summary, :by_employee, :by_beneficiary, :by_payment_method]
  
  def index
    if current_user.admin?
      @staff_discounts = StaffDiscount.includes(:user, :order, :staff_beneficiary).all
    else
      @staff_discounts = current_user.staff_discounts.includes(:order, :staff_beneficiary)
    end
    
    render json: @staff_discounts
  end
  
  def update
    @staff_discount = StaffDiscount.find(params[:id])
    
    if params[:mark_as_paid] == 'true' && @staff_discount.payment_method == 'house_account'
      @staff_discount.mark_as_paid!
      
      # Update user's house account balance if not already paid
      if !@staff_discount.is_paid
        @staff_discount.user.pay_house_account!(@staff_discount.original_amount - @staff_discount.discount_amount)
      end
      
      render json: @staff_discount
    else
      render json: { error: "Invalid operation" }, status: :unprocessable_entity
    end
  end
  
  def summary
    # Handle both direct parameters and nested parameters
    start_date = params[:start_date] || params.dig(:params, :start_date) || 30.days.ago.to_date
    end_date = params[:end_date] || params.dig(:params, :end_date) || Date.today
    
    # Use a default restaurant_id if current_user.restaurant_id is nil
    restaurant_id = current_user&.restaurant_id || 1
    
    summary = StaffDiscountReportService.generate_summary(
      restaurant_id,
      start_date,
      end_date
    )
    
    # Ensure we're returning a valid summary object even if no data is found
    if summary.nil?
      summary = {
        total_count: 0,
        total_discount_amount: 0,
        total_original_amount: 0,
        avg_discount_percentage: 0,
        working_count: 0,
        non_working_count: 0,
        house_account_count: 0,
        immediate_payment_count: 0
      }
    end
    
    render json: { summary: summary }
  end

  def by_employee
    # Handle both direct parameters and nested parameters
    start_date = params[:start_date] || params.dig(:params, :start_date) || 30.days.ago.to_date
    end_date = params[:end_date] || params.dig(:params, :end_date) || Date.today
    
    # Use a default restaurant_id if current_user.restaurant_id is nil
    restaurant_id = current_user&.restaurant_id || 1
    
    employees = StaffDiscountReportService.by_employee(
      restaurant_id,
      start_date,
      end_date
    )
    
    # Ensure we're returning a valid array even if no data is found
    employees ||= []
    
    render json: { employees: employees }
  end

  def by_beneficiary
    # Handle both direct parameters and nested parameters
    start_date = params[:start_date] || params.dig(:params, :start_date) || 30.days.ago.to_date
    end_date = params[:end_date] || params.dig(:params, :end_date) || Date.today
    
    # Use a default restaurant_id if current_user.restaurant_id is nil
    restaurant_id = current_user&.restaurant_id || 1
    
    beneficiaries = StaffDiscountReportService.by_beneficiary(
      restaurant_id,
      start_date,
      end_date
    )
    
    # Ensure we're returning a valid array even if no data is found
    beneficiaries ||= []
    
    render json: { beneficiaries: beneficiaries }
  end

  def by_payment_method
    # Handle both direct parameters and nested parameters
    start_date = params[:start_date] || params.dig(:params, :start_date) || 30.days.ago.to_date
    end_date = params[:end_date] || params.dig(:params, :end_date) || Date.today
    
    # Use a default restaurant_id if current_user.restaurant_id is nil
    restaurant_id = current_user&.restaurant_id || 1
    
    payment_methods = StaffDiscountReportService.by_payment_method(
      restaurant_id,
      start_date,
      end_date
    )
    
    # Ensure we're returning a valid array even if no data is found
    payment_methods ||= []
    
    render json: { payment_methods: payment_methods }
  end
  
  private
  
  def authorize_admin
    unless current_user&.admin?
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
  
  # Override public_endpoint? to allow analytics endpoints without restaurant_id
  def public_endpoint?
    ['summary', 'by_employee', 'by_beneficiary', 'by_payment_method'].include?(action_name)
  end
end
