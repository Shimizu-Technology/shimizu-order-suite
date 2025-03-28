class OrderPayment < ApplicationRecord
  belongs_to :order

  validates :payment_type, inclusion: { in: [ "initial", "additional", "refund" ] }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  
  # Validations for cash payments
  validates :cash_received, presence: true, numericality: { greater_than_or_equal_to: :amount }, if: -> { payment_method == 'cash' }
  
  # Before save callback to ensure change_due is calculated
  before_save :ensure_change_calculated, if: -> { payment_method == 'cash' && cash_received.present? }

  # For refunds, amount should not exceed the order total
  validate :refund_amount_valid, if: -> { payment_type == "refund" }

  # Helper method to get refunded items from either direct column or payment_details
  def get_refunded_items
    # First check direct column
    return refunded_items if refunded_items.present?

    # Then check payment_details
    return payment_details["refunded_items"] if payment_details.present? && payment_details["refunded_items"].present?

    # Return empty array if nothing found
    []
  end

  # Helper method to calculate change
  def calculate_change
    return 0 unless payment_method == 'cash' && cash_received.present?
    [cash_received - amount, 0].max
  end

  private

  # Ensure change_due is calculated before saving
  def ensure_change_calculated
    self.change_due = calculate_change
  end

  def refund_amount_valid
    total_paid = order.order_payments
                      .where(payment_type: [ "initial", "additional" ], status: "paid")
                      .sum(:amount)

    total_refunded = order.order_payments
                          .where(payment_type: "refund", status: "completed")
                          .where.not(id: id) # Exclude current refund if it's an update
                          .sum(:amount)

    max_refundable = total_paid - total_refunded

    if amount > max_refundable
      errors.add(:amount, "cannot exceed refundable amount of #{max_refundable}")
    end
  end
end
