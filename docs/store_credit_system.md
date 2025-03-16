# Store Credit System

The Store Credit system allows restaurants to issue and manage credit balances for customers, which can be used for future purchases. This document provides a comprehensive overview of the system's architecture, implementation, and usage.

## Overview

Store Credits provide a way for restaurants to:
- Issue refunds as store credit instead of processing payment reversals
- Reward loyal customers with credit for future purchases
- Handle compensation for service issues
- Implement gift card functionality

## Database Schema

### Store Credit Model

The `StoreCredit` model is the core of the system:

```ruby
# app/models/store_credit.rb
class StoreCredit < ApplicationRecord
  apply_default_scope
  belongs_to :user
  belongs_to :restaurant
  
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :expires_at, presence: true, if: -> { !never_expires }
  
  scope :active, -> { where("expires_at > ? OR never_expires = ?", Time.current, true) }
  scope :expired, -> { where("expires_at <= ? AND never_expires = ?", Time.current, false) }
  
  before_validation :set_default_expiration, on: :create
  
  attribute :transaction_history, :jsonb, default: []
  
  def add_transaction(amount, description, reference_type = nil, reference_id = nil)
    transaction = {
      amount: amount,
      description: description,
      timestamp: Time.current,
      reference_type: reference_type,
      reference_id: reference_id
    }
    
    self.transaction_history = transaction_history + [transaction]
    save!
  end
  
  def expired?
    !never_expires && expires_at <= Time.current
  end
  
  private
  
  def set_default_expiration
    return if expires_at.present? || never_expires
    
    # Default expiration is 1 year from creation
    self.expires_at = 1.year.from_now
  end
end
```

### Migration

The database migration for store credits:

```ruby
class CreateStoreCredits < ActiveRecord::Migration[7.0]
  def change
    create_table :store_credits do |t|
      t.references :user, null: false, foreign_key: true
      t.references :restaurant, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, default: 0.0, null: false
      t.datetime :expires_at
      t.boolean :never_expires, default: false
      t.jsonb :transaction_history, default: []
      t.string :source_type
      t.bigint :source_id
      t.text :notes

      t.timestamps
    end
    
    add_index :store_credits, [:source_type, :source_id]
    add_index :store_credits, [:user_id, :restaurant_id]
  end
end
```

## API Endpoints

The Store Credit system exposes the following API endpoints:

### Get Store Credit Balance

```
GET /store_credits
```

**Response:**
```json
{
  "store_credits": [
    {
      "id": 1,
      "amount": 25.00,
      "expires_at": "2026-03-15T14:30:00Z",
      "never_expires": false,
      "transaction_history": [
        {
          "amount": 25.00,
          "description": "Refund for order #1234",
          "timestamp": "2025-03-15T14:30:00Z",
          "reference_type": "Order",
          "reference_id": 1234
        }
      ]
    }
  ],
  "total_balance": 25.00
}
```

### Add Store Credit

```
POST /store_credits/add
```

**Request Body:**
```json
{
  "amount": 15.00,
  "notes": "Compensation for delayed order",
  "expires_at": "2026-03-15T00:00:00Z",
  "never_expires": false,
  "source_type": "Order",
  "source_id": 1234
}
```

**Response:**
```json
{
  "id": 2,
  "amount": 15.00,
  "expires_at": "2026-03-15T00:00:00Z",
  "never_expires": false,
  "transaction_history": [
    {
      "amount": 15.00,
      "description": "Compensation for delayed order",
      "timestamp": "2025-03-15T15:45:00Z",
      "reference_type": "Order",
      "reference_id": 1234
    }
  ]
}
```

### Use Store Credit

```
POST /store_credits/use
```

**Request Body:**
```json
{
  "amount": 10.00,
  "order_id": 5678
}
```

**Response:**
```json
{
  "amount_used": 10.00,
  "remaining_balance": 30.00,
  "order_id": 5678
}
```

## Integration with Order Payment System

The Store Credit system integrates with the Order Payment system to allow customers to use their store credit during checkout:

### Payment Flow

1. During checkout, the system checks for available store credit for the user
2. If store credit is available, it's presented as a payment option
3. The user can choose to apply some or all of their store credit to the order
4. When applied, a new `OrderPayment` record is created with `payment_method: 'store_credit'`
5. The store credit balance is reduced accordingly

```ruby
# Example code from OrderPaymentsController
def create
  # ... other payment method handling ...
  
  if params[:payment_method] == 'store_credit'
    store_credit_amount = [params[:amount].to_f, current_user.available_store_credit].min
    
    if store_credit_amount > 0
      @order_payment = OrderPayment.new(
        order: @order,
        amount: store_credit_amount,
        payment_method: 'store_credit',
        status: 'completed',
        payment_details: { store_credit_used: true }
      )
      
      if @order_payment.save
        current_user.use_store_credit(
          store_credit_amount, 
          "Used for order ##{@order.id}",
          'Order',
          @order.id
        )
        
        # Update order payment status if fully paid
        @order.update_payment_status
        
        render json: @order_payment, status: :created
      else
        render json: @order_payment.errors, status: :unprocessable_entity
      end
    else
      render json: { error: 'Insufficient store credit' }, status: :unprocessable_entity
    end
  end
  
  # ... other payment method handling ...
end
```

### Refund to Store Credit

When processing refunds, the system allows refunding to store credit instead of the original payment method:

```ruby
# Example code from OrderPaymentsController
def refund
  # ... validation and setup ...
  
  if params[:refund_to_store_credit] && @order.user.present?
    store_credit = StoreCredit.create!(
      user: @order.user,
      restaurant: @order.restaurant,
      amount: params[:amount],
      source_type: 'Order',
      source_id: @order.id,
      notes: "Refund for order ##{@order.id}"
    )
    
    store_credit.add_transaction(
      params[:amount],
      "Refund for order ##{@order.id}",
      'Order',
      @order.id
    )
    
    @order_payment = OrderPayment.create!(
      order: @order,
      amount: -params[:amount].to_f,
      payment_method: 'refund_to_store_credit',
      status: 'completed',
      payment_details: {
        refunded_items: params[:refunded_items],
        store_credit_id: store_credit.id
      }
    )
    
    render json: { 
      order_payment: @order_payment,
      store_credit: store_credit
    }, status: :created
  else
    # Process refund to original payment method
    # ...
  end
end
```

## Frontend Integration

The frontend integrates with the Store Credit system in several key areas:

1. **Checkout Page**: Displays available store credit and allows applying it to the order
2. **User Profile**: Shows store credit balance and transaction history
3. **Admin Order Management**: Provides options to issue refunds as store credit
4. **Admin Customer Management**: Allows adding store credit to customer accounts

### Example: Applying Store Credit at Checkout

```tsx
// src/ordering/components/payment/StoreCredit.tsx
import React, { useState, useEffect } from 'react';
import { useStoreCredit } from '../../hooks/useStoreCredit';
import { formatCurrency } from '../../../shared/utils/formatters';

interface StoreCreditProps {
  orderTotal: number;
  onApplyStoreCredit: (amount: number) => void;
}

const StoreCredit: React.FC<StoreCreditProps> = ({ orderTotal, onApplyStoreCredit }) => {
  const { storeCredit, isLoading } = useStoreCredit();
  const [amountToUse, setAmountToUse] = useState(0);
  
  useEffect(() => {
    // Default to using all available store credit up to the order total
    if (storeCredit && storeCredit.total_balance > 0) {
      setAmountToUse(Math.min(storeCredit.total_balance, orderTotal));
    }
  }, [storeCredit, orderTotal]);
  
  if (isLoading) return <div>Loading store credit information...</div>;
  
  if (!storeCredit || storeCredit.total_balance === 0) {
    return null;
  }
  
  const handleAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = parseFloat(e.target.value);
    if (isNaN(value)) {
      setAmountToUse(0);
    } else {
      setAmountToUse(Math.min(value, storeCredit.total_balance, orderTotal));
    }
  };
  
  const handleApply = () => {
    onApplyStoreCredit(amountToUse);
  };
  
  return (
    <div className="store-credit-container">
      <h3>Store Credit</h3>
      <p>Available Balance: {formatCurrency(storeCredit.total_balance)}</p>
      
      <div className="input-group">
        <label htmlFor="store-credit-amount">Amount to Use:</label>
        <input
          id="store-credit-amount"
          type="number"
          min="0"
          max={Math.min(storeCredit.total_balance, orderTotal)}
          step="0.01"
          value={amountToUse}
          onChange={handleAmountChange}
        />
      </div>
      
      <button 
        className="apply-credit-btn"
        onClick={handleApply}
        disabled={amountToUse <= 0}
      >
        Apply Store Credit
      </button>
    </div>
  );
};

export default StoreCredit;
```

## Admin Interface

The admin interface provides several tools for managing store credits:

1. **View Customer Store Credit**: Admins can view a customer's store credit balance and transaction history
2. **Add Store Credit**: Admins can add store credit to a customer's account
3. **Adjust Store Credit**: Admins can adjust store credit amounts or expiration dates
4. **Issue Refunds as Store Credit**: When processing refunds, admins can choose to issue the refund as store credit

### Example: Admin Store Credit Management

```tsx
// src/ordering/components/admin/customer/StoreCreditManager.tsx
import React, { useState } from 'react';
import { useStoreCredit } from '../../../hooks/useStoreCredit';
import { formatCurrency, formatDate } from '../../../../shared/utils/formatters';
import { addStoreCredit } from '../../../../shared/api/endpoints/storeCredits';

interface StoreCreditManagerProps {
  userId: number;
}

const StoreCreditManager: React.FC<StoreCreditManagerProps> = ({ userId }) => {
  const { storeCredit, isLoading, refetch } = useStoreCredit(userId);
  const [amount, setAmount] = useState('');
  const [notes, setNotes] = useState('');
  const [neverExpires, setNeverExpires] = useState(false);
  const [expiresAt, setExpiresAt] = useState(
    new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString().split('T')[0]
  );
  
  const handleAddCredit = async () => {
    try {
      await addStoreCredit({
        user_id: userId,
        amount: parseFloat(amount),
        notes,
        never_expires: neverExpires,
        expires_at: neverExpires ? null : `${expiresAt}T23:59:59Z`
      });
      
      // Reset form
      setAmount('');
      setNotes('');
      
      // Refresh store credit data
      refetch();
    } catch (error) {
      console.error('Failed to add store credit:', error);
    }
  };
  
  if (isLoading) return <div>Loading...</div>;
  
  return (
    <div className="store-credit-manager">
      <h2>Store Credit Management</h2>
      
      {storeCredit && (
        <div className="current-balance">
          <h3>Current Balance: {formatCurrency(storeCredit.total_balance)}</h3>
          
          <h4>Credit Details</h4>
          <table className="credit-table">
            <thead>
              <tr>
                <th>Amount</th>
                <th>Expires</th>
                <th>Notes</th>
                <th>Last Transaction</th>
              </tr>
            </thead>
            <tbody>
              {storeCredit.store_credits.map(credit => (
                <tr key={credit.id}>
                  <td>{formatCurrency(credit.amount)}</td>
                  <td>
                    {credit.never_expires 
                      ? 'Never' 
                      : formatDate(credit.expires_at)}
                  </td>
                  <td>{credit.notes}</td>
                  <td>
                    {credit.transaction_history.length > 0 && (
                      <div>
                        {credit.transaction_history[credit.transaction_history.length - 1].description}
                        <br />
                        <small>
                          {formatDate(credit.transaction_history[credit.transaction_history.length - 1].timestamp)}
                        </small>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      
      <div className="add-credit-form">
        <h3>Add Store Credit</h3>
        
        <div className="form-group">
          <label htmlFor="amount">Amount</label>
          <input
            id="amount"
            type="number"
            min="0.01"
            step="0.01"
            value={amount}
            onChange={e => setAmount(e.target.value)}
            required
          />
        </div>
        
        <div className="form-group">
          <label htmlFor="notes">Notes</label>
          <textarea
            id="notes"
            value={notes}
            onChange={e => setNotes(e.target.value)}
            placeholder="Reason for adding credit"
          />
        </div>
        
        <div className="form-group">
          <label>
            <input
              type="checkbox"
              checked={neverExpires}
              onChange={e => setNeverExpires(e.target.checked)}
            />
            Never Expires
          </label>
        </div>
        
        {!neverExpires && (
          <div className="form-group">
            <label htmlFor="expires-at">Expires On</label>
            <input
              id="expires-at"
              type="date"
              value={expiresAt}
              onChange={e => setExpiresAt(e.target.value)}
              min={new Date().toISOString().split('T')[0]}
            />
          </div>
        )}
        
        <button 
          className="add-credit-btn"
          onClick={handleAddCredit}
          disabled={!amount || parseFloat(amount) <= 0}
        >
          Add Credit
        </button>
      </div>
    </div>
  );
};

export default StoreCreditManager;
```

## Best Practices

When working with the Store Credit system, follow these best practices:

1. **Always Use Transactions**: When modifying store credit balances, use database transactions to ensure data consistency
2. **Maintain Audit Trail**: Always record transactions in the `transaction_history` field
3. **Check Expiration**: Always check if store credit has expired before allowing its use
4. **Handle Partial Usage**: When a user has multiple store credit entries, use the oldest ones first (closest to expiration)
5. **Secure Admin Actions**: Ensure that all admin actions related to store credit are properly authorized

## Troubleshooting

Common issues and their solutions:

1. **Missing Store Credit Balance**: Ensure the user is properly authenticated and the restaurant context is set
2. **Failed to Apply Credit**: Check that the store credit hasn't expired and has sufficient balance
3. **Refund Issues**: Verify that the refund amount doesn't exceed the original payment amount
4. **Transaction History Discrepancies**: Ensure all modifications to store credit use the `add_transaction` method

## Future Enhancements

Planned enhancements for the Store Credit system:

1. **Gift Cards**: Extend the system to support purchasable gift cards
2. **Loyalty Program Integration**: Connect store credits with the loyalty program
3. **Transferable Credits**: Allow users to transfer store credit to other users
4. **Automatic Expiration Notifications**: Send notifications when store credit is about to expire
