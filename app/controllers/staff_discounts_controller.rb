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
    start_date = params[:start_date] || 30.days.ago.to_date
    end_date = params[:end_date] || Date.today
    
    summary = StaffDiscountReportService.generate_summary(
      current_user.restaurant_id,
      start_date,
      end_date
    )
    
    render json: { summary: summary }
  end

  def by_employee
    start_date = params[:start_date] || 30.days.ago.to_date
    end_date = params[:end_date] || Date.today
    
    employees = StaffDiscountReportService.by_employee(
      current_user.restaurant_id,
      start_date,
      end_date
    )
    
    render json: { employees: employees }
  end

  def by_beneficiary
    start_date = params[:start_date] || 30.days.ago.to_date
    end_date = params[:end_date] || Date.today
    
    beneficiaries = StaffDiscountReportService.by_beneficiary(
      current_user.restaurant_id,
      start_date,
      end_date
    )
    
    render json: { beneficiaries: beneficiaries }
  end

  def by_payment_method
    start_date = params[:start_date] || 30.days.ago.to_date
    end_date = params[:end_date] || Date.today
    
    payment_methods = StaffDiscountReportService.by_payment_method(
      current_user.restaurant_id,
      start_date,
      end_date
    )
    
    render json: { payment_methods: payment_methods }
  end
  
  private
  
  def authorize_admin
    unless current_user&.admin?
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
end
