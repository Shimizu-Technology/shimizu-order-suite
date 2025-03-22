class StaffDiscount < ApplicationRecord
  belongs_to :order
  belongs_to :user
  belongs_to :staff_beneficiary, optional: true
  
  validates :discount_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :original_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :is_working, inclusion: { in: [true, false] }
  validates :payment_method, presence: true, inclusion: { in: ['immediate', 'house_account'] }
  
  # Calculate discount percentage based on working status
  def self.calculate_discount_percentage(is_working)
    is_working ? 0.5 : 0.3  # 50% if working, 30% if not
  end
  
  # Calculate discounted amount
  def self.calculate_discounted_amount(original_amount, is_working)
    discount_percentage = calculate_discount_percentage(is_working)
    discount_amount = original_amount * discount_percentage
    discounted_amount = original_amount - discount_amount
    
    return {
      original_amount: original_amount,
      discount_amount: discount_amount,
      discounted_amount: discounted_amount
    }
  end
  
  # Mark as paid
  def mark_as_paid!
    update(is_paid: true, paid_at: Time.current)
  end
end
