class StaffMember < ApplicationRecord
  # Associations
  belongs_to :user, optional: true
  has_many :orders, foreign_key: :staff_member_id, dependent: :nullify
  has_many :created_orders, class_name: 'Order', foreign_key: :created_by_staff_id, dependent: :nullify
  has_many :house_account_transactions, dependent: :destroy
  
  # Validations
  validates :name, presence: true
  validates :house_account_balance, numericality: { greater_than_or_equal_to: 0 }
  validates :user_id, uniqueness: true, allow_nil: true
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :with_house_account_balance, -> { where('house_account_balance > 0') }
  
  # Methods
  
  # Add a transaction to the house account
  def add_house_account_transaction(amount, transaction_type, description, order = nil, created_by = nil)
    transaction = house_account_transactions.create!(
      amount: amount,
      transaction_type: transaction_type,
      description: description,
      order_id: order&.id,
      order_number: order&.order_number,
      created_by_id: created_by&.id
    )
    
    # Update the balance
    new_balance = house_account_balance + amount
    update!(house_account_balance: new_balance)
    
    transaction
  end
  
  # Charge an order to the house account
  def charge_order_to_house_account(order, created_by = nil)
    # Use order_number if available, otherwise fall back to id
    order_identifier = order.order_number.present? ? order.order_number : order.id.to_s
    add_house_account_transaction(
      order.total,
      'order',
      "Order ##{order_identifier}",
      order,
      created_by
    )
  end
  
  # Process a payment to the house account
  def process_payment(amount, reference, created_by = nil)
    add_house_account_transaction(
      -amount, # Negative amount for payments
      'payment',
      "Payment - #{reference}",
      nil,
      created_by
    )
  end
  
  # Get all staff orders for this staff member
  def staff_orders
    orders.where(is_staff_order: true)
  end
  
  # Get total spent on house account
  def total_house_account_spent
    house_account_transactions.where(transaction_type: 'order').sum(:amount)
  end
  
  # Get total payments made to house account
  def total_house_account_payments
    house_account_transactions.where(transaction_type: 'payment').sum(:amount).abs
  end
  
  # As JSON for API responses
  def as_json(options = {})
    super(options).merge(
      total_orders: staff_orders.count,
      house_account_balance: house_account_balance.to_f,
      user_name: user ? "#{user.first_name} #{user.last_name}" : nil
    )
  end
end
