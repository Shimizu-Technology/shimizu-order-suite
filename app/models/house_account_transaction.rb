class HouseAccountTransaction < ApplicationRecord
  # Associations
  belongs_to :staff_member
  belongs_to :order, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  
  # Validations
  validates :amount, presence: true, numericality: true
  validates :transaction_type, presence: true, inclusion: { in: ['order', 'payment', 'adjustment', 'charge'] }
  validates :description, presence: true
  
  # Scopes
  scope :orders, -> { where(transaction_type: 'order') }
  scope :payments, -> { where(transaction_type: 'payment') }
  scope :adjustments, -> { where(transaction_type: 'adjustment') }
  scope :recent, -> { order(created_at: :desc) }
  
  # Methods
  
  # Is this a charge (positive amount) or a payment (negative amount)?
  def charge?
    amount > 0
  end
  
  def payment?
    amount < 0
  end
  
  # Get the absolute amount (for display purposes)
  def absolute_amount
    amount.abs
  end
  
  # As JSON for API responses
  def as_json(options = {})
    super(options).merge(
      staff_member_name: staff_member&.name,
      order_number: order&.id,
      created_by_name: created_by&.full_name,
      created_at_formatted: created_at&.strftime('%Y-%m-%d %H:%M'),
      amount_formatted: sprintf('$%.2f', amount.abs),
      transaction_type_formatted: transaction_type.titleize
    )
  end
end
