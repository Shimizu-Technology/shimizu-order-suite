# Staff Discount System

This document outlines the Staff Discount System implementation, which allows staff members to receive discounts on their orders and provides options for immediate payment or using a house account.

## Overview

The Staff Discount System provides the following features:

1. Staff members can place orders with special discounts:
   - 50% discount when they're working
   - 30% discount when they're not working

2. Payment options:
   - Immediate payment with the discounted amount
   - House Account (deferred payment) where the amount is tracked and can be deducted from their paycheck

3. Beneficiary tracking:
   - Orders can be placed for the staff member or for other beneficiaries (e.g., family members)
   - All beneficiaries are tracked for reporting purposes

4. Robust reporting:
   - Track all staff discounts, including who used them, when, and how much was discounted
   - Track house account balances for each staff member

## Database Structure

The system uses three primary models:

### 1. StaffBeneficiary

```ruby
# app/models/staff_beneficiary.rb
class StaffBeneficiary < ApplicationRecord
  belongs_to :restaurant
  has_many :staff_discounts
  
  validates :name, presence: true, uniqueness: { scope: :restaurant_id }
  
  scope :active, -> { where(active: true) }
end
```

This model tracks the beneficiaries of staff discounts (e.g., "Self", "Spouse", "Child").

### 2. StaffDiscount

```ruby
# app/models/staff_discount.rb
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
```

This model tracks each individual staff discount applied to an order.

### 3. User (extended)

The User model was extended with methods to support house accounts:

```ruby
# House account methods in User model
def staff?
  role == "admin" || role == "staff"
end

def update_house_account_balance!(amount)
  update!(house_account_balance: house_account_balance + amount)
end

def pay_house_account!(amount = nil)
  amount ||= house_account_balance
  amount = [amount, house_account_balance].min
  
  if amount > 0
    update!(house_account_balance: house_account_balance - amount)
  end
  
  return amount
end
```

## How to Use

### Checkout Process

When a staff member is checking out:

1. They can indicate they're placing a staff order by setting `is_staff_order` to `true`
2. They can specify whether they're working (`staff_is_working: true/false`)
3. They can select their payment method (`staff_payment_method: 'immediate'/'house_account'`)
4. They can select a beneficiary (`staff_beneficiary_id`) if the order is for someone other than themselves

The system will:
- Calculate the appropriate discount (50% or 30%) based on working status
- Apply the discount to the order total
- Create a staff discount record to track the discount
- If using house account, update the staff member's house account balance

### House Account Management

Administrators can:
1. View all staff discounts via the StaffDiscount model
2. See each user's current house account balance
3. Mark house account payments as paid when processed (e.g., during payroll)

## API Endpoints

The following API endpoints are available for the staff discount system:

### Staff Beneficiaries

- `GET /staff_beneficiaries` - List all active staff beneficiaries
- `POST /staff_beneficiaries` - Create a new staff beneficiary

### Staff Discounts

- `GET /staff_discounts` - List all staff discounts (admin) or just the current user's discounts (staff)
- `PATCH /staff_discounts/:id` - Update a staff discount (e.g., mark as paid)

## Frontend Implementation

On the frontend side, the checkout page should be updated to:

1. Show a "Staff Order" checkbox for staff users
2. When checked, display additional options:
   - Working status (Yes/No)
   - Payment method (Immediate/House Account)
   - Beneficiary selector

When the order is submitted, these fields should be included in the order payload.

## Reporting

Consider implementing additional reports such as:
- Total discounts used by each staff member
- House account balances for all staff
- Discount usage by time period
- Discount usage by beneficiary

## Security Considerations

The system ensures that:
- Only administrators can view all staff discounts
- Staff members can only view their own discounts
- Only administrators can mark house account payments as paid
