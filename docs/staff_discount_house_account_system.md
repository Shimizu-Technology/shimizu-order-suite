# Staff Discount and House Account System

This document provides a comprehensive overview of the Staff Discount and House Account system in Hafaloha, explaining how it allows restaurants to provide discounted meals to staff members and track purchases for payroll deduction.

## Overview

The Staff Discount and House Account system enables restaurants to:
- Provide discounted meals to staff members based on duty status
- Track staff orders separately from regular customer orders
- Allow staff to charge purchases to a house account for later payroll deduction
- Generate comprehensive reports on staff discount usage and house account balances

## Core Components

### Database Schema

#### Staff Member Model

The `StaffMember` model is the central component of the system:

```ruby
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
  
  # Methods to manage house account transactions
  def add_house_account_transaction(amount, transaction_type, description, order = nil, created_by = nil)
    transaction = house_account_transactions.create!(
      amount: amount,
      transaction_type: transaction_type,
      description: description,
      order_id: order&.id,
      created_by_id: created_by&.id
    )
    
    # Update the balance
    new_balance = house_account_balance + amount
    update!(house_account_balance: new_balance)
    
    transaction
  end
  
  def charge_order_to_house_account(order, created_by = nil)
    add_house_account_transaction(
      order.total,
      'order',
      "Order ##{order.id}",
      order,
      created_by
    )
  end
  
  def process_payment(amount, reference, created_by = nil)
    add_house_account_transaction(
      -amount, # Negative amount for payments
      'payment',
      "Payment - #{reference}",
      nil,
      created_by
    )
  end
end
```

#### House Account Transaction Model

The `HouseAccountTransaction` model tracks all changes to house account balances:

```ruby
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
  
  # Helper methods
  def charge?
    amount > 0
  end
  
  def payment?
    amount < 0
  end
  
  def absolute_amount
    amount.abs
  end
end
```

#### Order Model Extensions

The Order model has been extended to support staff discounts and house account integration:

```ruby
class Order < ApplicationRecord
  # Staff discount constants
  STAFF_ON_DUTY_DISCOUNT = 0.5  # 50% discount
  STAFF_OFF_DUTY_DISCOUNT = 0.3  # 30% discount
  
  # Staff order associations
  belongs_to :staff_member, optional: true
  belongs_to :created_by_staff, class_name: 'StaffMember', foreign_key: 'created_by_staff_id', optional: true
  has_many :house_account_transactions, dependent: :nullify
  
  # Staff order attributes
  # is_staff_order: boolean - Indicates if this is a staff order
  # staff_member_id: integer - References the staff member the order is for
  # staff_on_duty: boolean - Indicates if the staff member is on duty
  # use_house_account: boolean - Indicates if the order should be charged to a house account
  # created_by_staff_id: integer - References the staff member who created the order
  # pre_discount_total: decimal - Total before staff discount is applied
  
  # Staff discount helper methods
  def staff_discount_rate
    return 0 unless is_staff_order
    staff_on_duty ? STAFF_ON_DUTY_DISCOUNT : STAFF_OFF_DUTY_DISCOUNT
  end
  
  def calculate_pre_discount_total
    return pre_discount_total if pre_discount_total.present?
    
    # Sum up the price of all items
    items_total = items.sum { |item| (item['price'].to_f * item['quantity'].to_i) }
    
    # Add merchandise items if present
    merch_total = 0
    if merchandise_items.present?
      merch_total = merchandise_items.sum { |item| (item['price'].to_f * item['quantity'].to_i) }
    end
    
    items_total + merch_total
  end
  
  def discount_amount
    return 0 unless is_staff_order
    calculate_pre_discount_total * staff_discount_rate
  end
  
  # Apply staff discount to the order
  def apply_staff_discount
    return unless is_staff_order
    
    # Set the pre-discount total if not already set
    self.pre_discount_total ||= calculate_pre_discount_total
    
    # Calculate the discounted total
    discounted_total = pre_discount_total * (1 - staff_discount_rate)
    
    # Update the total
    self.total = discounted_total.round(2)
    
    # Store the pre-discount price for each item
    if items.present?
      items_with_pre_discount = items.map do |item|
        # Store the original price as pre_discount_price
        item_price = item['price'].to_f
        item.merge({
          'pre_discount_price' => item_price,
          'price' => (item_price * (1 - staff_discount_rate)).round(2)
        })
      end
      self.items = items_with_pre_discount
    end
  end
  
  # Process house account payment if needed
  def process_house_account
    return unless is_staff_order && use_house_account && staff_member.present?
    
    # Add a transaction to the staff member's house account
    transaction = staff_member.charge_order_to_house_account(self, created_by_staff)
    
    # Mark the payment as completed via house account
    self.payment_method = 'house_account'
    self.payment_status = 'completed'
    self.payment_amount = total
  end
  
  # Callbacks for staff orders
  before_save :apply_staff_discount, if: -> { is_staff_order && (new_record? || is_staff_order_changed? || staff_on_duty_changed?) }
  after_create :process_house_account, if: -> { is_staff_order && use_house_account }
end
```

## API Endpoints

### Staff Members

```
GET /api/staff_members - List all staff members
POST /api/staff_members - Create a new staff member
GET /api/staff_members/:id - Get a specific staff member
PUT /api/staff_members/:id - Update a staff member
DELETE /api/staff_members/:id - Delete a staff member
```

### House Account Transactions

```
GET /api/staff_members/:id/transactions - List transactions for a staff member
POST /api/staff_members/:id/transactions - Create a new transaction
PUT /api/staff_members/:id/transactions/:transaction_id - Update a transaction
```

### Reports

```
GET /api/reports/house_account_balances - Current balances for all staff
GET /api/reports/staff_orders - Staff order history with filtering
GET /api/reports/discount_summary - Discount analysis
GET /api/reports/house_account_activity/:staff_id - House account transactions
```

## Frontend Implementation

### Staff Order Modal

The frontend implements a Staff Order Modal that allows staff members to:
- Toggle staff order mode
- Select the staff member
- Set duty status (on/off duty)
- Choose between immediate payment or house account
- See the calculated discount and final total

```tsx
// Staff order info in StaffOrderModal.tsx
const [isStaffOrder, setIsStaffOrder] = useState(false);
const [staffMemberId, setStaffMemberId] = useState<number | null>(null);
const [staffOnDuty, setStaffOnDuty] = useState(false);
const [useHouseAccount, setUseHouseAccount] = useState(false);
const [createdByStaffId, setCreatedByStaffId] = useState<number | null>(null);
const [preDiscountTotal, setPreDiscountTotal] = useState(0);

// Calculate discounted total for staff orders
const orderTotal = useMemo(() => {
  if (isStaffOrder && staffMemberId) {
    // Apply staff discount based on duty status
    if (staffOnDuty) {
      // 50% discount for on-duty staff
      return rawTotal * 0.5;
    } else {
      // 30% discount for off-duty staff
      return rawTotal * 0.7;
    }
  }
  // No discount for regular orders
  return rawTotal;
}, [rawTotal, isStaffOrder, staffMemberId, staffOnDuty]);
```

### Staff Order Options Component

The `StaffOrderOptions` component provides the UI for selecting staff order parameters:

```tsx
export function StaffOrderOptions({
  isStaffOrder,
  staffMemberId,
  setStaffMemberId,
  staffOnDuty,
  setStaffOnDuty,
  useHouseAccount,
  setUseHouseAccount,
  setCreatedByStaffId
}: StaffOrderOptionsProps) {
  const [staffMembers, setStaffMembers] = useState<StaffMember[]>([]);
  const currentUser = useAuthStore(state => state.user);

  // Fetch staff members when component mounts
  useEffect(() => {
    if (isStaffOrder) {
      fetchStaffMembers();
    }
  }, [isStaffOrder]);

  // Get the selected staff member
  const selectedStaffMember = staffMemberId 
    ? staffMembers.find(staff => staff.id === staffMemberId) 
    : null;
    
  // House account should be available regardless of balance
  const canUseHouseAccount = !!selectedStaffMember;

  return (
    <div>
      {isStaffOrder && (
        <>
          {/* Staff Member Selection */}
          <div className="mb-2">
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Staff Member
            </label>
            <MobileSelect
              options={staffMembers.map(staff => ({
                value: staff.id.toString(),
                label: `${staff.name} - ${staff.position}`
              }))}
              value={staffMemberId ? staffMemberId.toString() : ''}
              onChange={(value) => setStaffMemberId(value ? parseInt(value) : null)}
              placeholder="Select Staff Member"
            />
          </div>

          {/* Staff On Duty */}
          <div className="flex items-center">
            <input
              id="staff-on-duty"
              type="checkbox"
              checked={staffOnDuty}
              onChange={(e) => setStaffOnDuty(e.target.checked)}
            />
            <label htmlFor="staff-on-duty" className="ml-1 text-xs font-medium text-gray-900">
              On duty (50% off)
            </label>
          </div>

          {/* Use House Account */}
          <div className="flex items-center">
            <input
              id="use-house-account"
              type="checkbox"
              checked={useHouseAccount}
              onChange={(e) => setUseHouseAccount(e.target.checked)}
              disabled={!canUseHouseAccount}
            />
            <label 
              htmlFor="use-house-account" 
              className={`ml-1 text-xs font-medium ${canUseHouseAccount ? 'text-gray-900' : 'text-gray-400'}`}
            >
              Use House Account
            </label>
          </div>

          {/* Display house account balance */}
          {selectedStaffMember && (
            <div className="text-xs text-gray-600 mb-2">
              Balance: ${selectedStaffMember.house_account_balance.toFixed(2)}
              {selectedStaffMember.house_account_balance > 0 && (
                <span className="text-yellow-600"> (deducted on payday)</span>
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
}
```

### Order Store Integration

The Order Store has been extended to handle staff order parameters:

```typescript
// In orderStore.ts - addOrder function
addOrder: async (
  items,
  total,
  specialInstructions,
  contactName,
  contactPhone,
  contactEmail,
  transactionId,
  paymentMethod = 'credit_card',
  vipCode,
  staffModal = false,
  paymentDetails = null
) => {
  // Extract staffOrderParams from paymentDetails if present
  const staffOrderParams = paymentDetails?.staffOrderParams || {};
  
  const payload = {
    order: {
      items: foodItems,
      merchandise_items: merchandiseItems,
      total,
      special_instructions: specialInstructions,
      contact_name: contactName,
      contact_phone: contactPhone,
      contact_email: contactEmail,
      transaction_id: transactionId,
      payment_method: paymentMethod,
      vip_code: vipCode,
      staff_modal: staffModal,
      payment_details: paymentDetails,
      // Include staff order parameters
      ...staffOrderParams
    },
  };
  
  // API call to create order
  const newOrder = await api.post<Order>('/orders', payload);
  
  return newOrder;
}
```

## Authorization

The Staff Discount and House Account system integrates with Hafaloha's role-based access control system:

### Staff Member Policy

```ruby
class StaffMemberPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.admin_or_above?
        # Admins and super admins can see all staff members
        scope.all
      elsif user.staff?
        # Staff can only see active staff members
        scope.active
      else
        # Regular users can't see staff members
        scope.none
      end
    end
  end

  def index?
    staff_or_above?
  end

  def show?
    staff_or_above?
  end

  def create?
    admin_or_above?
  end

  def update?
    admin_or_above?
  end

  def destroy?
    admin_or_above?
  end
  
  def add_transaction?
    admin_or_above?
  end
  
  def view_transactions?
    admin_or_above? || record.user_id == user.id
  end
end
```

### House Account Transaction Policy

```ruby
class HouseAccountTransactionPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.admin_or_above?
        # Admins and super admins can see all transactions
        scope.all
      elsif user.staff? && user.staff_member.present?
        # Staff can only see their own transactions
        scope.where(staff_member_id: user.staff_member.id)
      else
        # Regular users can't see transactions
        scope.none
      end
    end
  end

  def index?
    staff_or_above?
  end

  def show?
    admin_or_above? || (user.staff_member.present? && record.staff_member_id == user.staff_member.id)
  end

  def create?
    admin_or_above?
  end

  def update?
    admin_or_above?
  end
end
```

## Reports

The system provides several reports for tracking staff discounts and house account usage:

### House Account Balance Report

Shows current balance for each staff member, with options to mark as paid for payroll processing.

### Staff Order History Report

Detailed list of all staff orders with filtering by date range and staff member, showing pre-discount total, discount amount, and final total.

### Discount Summary Report

Summarizes the total retail value of staff orders, total discounted value, and discount amount, with breakdown by staff member and duty status.

### House Account Activity Report

Shows all charges and payments for a staff member with running balance and ability to add manual adjustments.

## Troubleshooting

### Common Issues

1. **Staff Discount Not Applied**: Ensure `is_staff_order` is set to true and a valid `staff_member_id` is provided
2. **House Account Not Charged**: Verify that `use_house_account` is set to true and the staff member exists
3. **Missing Transaction History**: Check that all house account modifications use the `add_house_account_transaction` method
4. **Incorrect Discount Rate**: Confirm that `staff_on_duty` is set correctly (true for 50% discount, false for 30% discount)

### Best Practices

1. Always use the `StaffOrderOptions` component for consistent staff order creation
2. Process payments through house accounts only after verifying the staff member's identity
3. Regularly review house account balances and process payroll deductions in a timely manner
4. Document all manual adjustments to house accounts with clear descriptions
