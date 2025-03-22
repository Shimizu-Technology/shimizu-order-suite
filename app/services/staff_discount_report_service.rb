# app/services/staff_discount_report_service.rb
class StaffDiscountReportService
  def self.generate_summary(restaurant_id, start_date, end_date)
    # Query to generate summary metrics
    discounts = StaffDiscount.joins(:order)
                            .where(orders: { restaurant_id: restaurant_id })
                            .where('staff_discounts.created_at BETWEEN ? AND ?', start_date, end_date)
    
    # Calculate total amounts
    total_count = discounts.count
    total_discount_amount = discounts.sum(:discount_amount)
    total_original_amount = discounts.sum(:original_amount)
    
    # Calculate average discount percentage
    avg_discount_percentage = total_original_amount > 0 ? 
                              (total_discount_amount / total_original_amount) * 100 : 0
    
    # Count by working status
    working_count = discounts.where(is_working: true).count
    non_working_count = discounts.where(is_working: false).count
    
    # Count by payment method
    house_account_count = discounts.where(payment_method: 'house_account').count
    immediate_payment_count = discounts.where(payment_method: 'immediate').count
    
    # Return aggregated data
    {
      total_count: total_count,
      total_discount_amount: total_discount_amount,
      total_original_amount: total_original_amount,
      avg_discount_percentage: avg_discount_percentage,
      working_count: working_count,
      non_working_count: non_working_count,
      house_account_count: house_account_count,
      immediate_payment_count: immediate_payment_count
    }
  end
  
  def self.by_employee(restaurant_id, start_date, end_date)
    # Get all staff users for the restaurant
    staff_users = User.where(restaurant_id: restaurant_id)
                      .where("role = 'admin' OR role = 'staff'")
    
    # For each staff user, calculate their discount usage
    staff_users.map do |user|
      # Get all discounts for this user
      discounts = StaffDiscount.joins(:order)
                              .where(user_id: user.id)
                              .where(orders: { restaurant_id: restaurant_id })
                              .where('staff_discounts.created_at BETWEEN ? AND ?', start_date, end_date)
      
      # Calculate metrics
      discount_count = discounts.count
      total_discount_amount = discounts.sum(:discount_amount)
      total_original_amount = discounts.sum(:original_amount)
      
      # Calculate average discount percentage
      avg_discount_percentage = total_original_amount > 0 ? 
                                (total_discount_amount / total_original_amount) * 100 : 0
      
      # Calculate house account usage
      house_account_usage = discounts.where(payment_method: 'house_account')
                                    .sum('original_amount - discount_amount')
      
      # Return user data with metrics
      {
        user_id: user.id,
        user_name: user.full_name,
        discount_count: discount_count,
        total_discount_amount: total_discount_amount,
        total_original_amount: total_original_amount,
        avg_discount_percentage: avg_discount_percentage,
        house_account_balance: user.house_account_balance,
        house_account_usage: house_account_usage
      }
    end
  end
  
  def self.by_beneficiary(restaurant_id, start_date, end_date)
    # Get all beneficiaries for the restaurant
    beneficiaries = StaffBeneficiary.where(restaurant_id: restaurant_id)
    
    # Start with "Self" (no beneficiary)
    result = [{
      beneficiary_id: nil,
      beneficiary_name: "Self",
      discount_count: 0,
      total_discount_amount: 0
    }]
    
    # For each beneficiary, calculate discount usage
    beneficiaries.each do |beneficiary|
      # Get all discounts for this beneficiary
      discounts = StaffDiscount.joins(:order)
                              .where(staff_beneficiary_id: beneficiary.id)
                              .where(orders: { restaurant_id: restaurant_id })
                              .where('staff_discounts.created_at BETWEEN ? AND ?', start_date, end_date)
      
      # Calculate metrics
      discount_count = discounts.count
      total_discount_amount = discounts.sum(:discount_amount)
      
      # Add to result
      result << {
        beneficiary_id: beneficiary.id,
        beneficiary_name: beneficiary.name,
        discount_count: discount_count,
        total_discount_amount: total_discount_amount
      }
    end
    
    # Update "Self" with actual data
    self_discounts = StaffDiscount.joins(:order)
                                 .where(staff_beneficiary_id: nil)
                                 .where(orders: { restaurant_id: restaurant_id })
                                 .where('staff_discounts.created_at BETWEEN ? AND ?', start_date, end_date)
    
    result[0][:discount_count] = self_discounts.count
    result[0][:total_discount_amount] = self_discounts.sum(:discount_amount)
    
    # Return only beneficiaries with at least one discount
    result.select { |b| b[:discount_count] > 0 }
  end
  
  def self.by_payment_method(restaurant_id, start_date, end_date)
    # Generate a date range
    date_range = (start_date.to_date..end_date.to_date).to_a
    
    # Initialize result with all dates
    result = date_range.map do |date|
      {
        date: date.strftime('%Y-%m-%d'),
        immediate_payment: 0,
        house_account: 0
      }
    end
    
    # Get all discounts grouped by date and payment method
    discounts = StaffDiscount.joins(:order)
                            .where(orders: { restaurant_id: restaurant_id })
                            .where('staff_discounts.created_at BETWEEN ? AND ?', start_date, end_date)
                            .group("DATE(staff_discounts.created_at)", "staff_discounts.payment_method")
                            .select("DATE(staff_discounts.created_at) as date", 
                                   "staff_discounts.payment_method", 
                                   "COUNT(*) as count")
    
    # Update result with actual counts
    discounts.each do |discount|
      date_str = discount.date.strftime('%Y-%m-%d')
      day_data = result.find { |d| d[:date] == date_str }
      
      if day_data
        if discount.payment_method == 'immediate'
          day_data[:immediate_payment] = discount.count
        elsif discount.payment_method == 'house_account'
          day_data[:house_account] = discount.count
        end
      end
    end
    
    result
  end
end
