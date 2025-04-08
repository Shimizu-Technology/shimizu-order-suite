# Manual Payment Options

This document describes the implementation of manual payment options in the Shimizu Order Suite ordering system, including Clover, Revel, and other payment methods.

## Overview

The system now supports multiple payment methods beyond the built-in Stripe and PayPal integrations. This allows staff to process payments through external systems like Clover or Revel POS systems, or to handle other manual payment methods, while still tracking the payment information within the Shimizu Order Suite system.

## Payment Methods

The following payment methods are now supported:

1. **Credit Card** (via Stripe or PayPal) - Existing functionality
2. **Cash** - Existing functionality
3. **Payment Link** - Existing functionality
4. **Clover** - New manual payment option
5. **Revel** - New manual payment option
6. **Other** - Generic option for any other payment method

## Implementation Details

### Frontend Changes

- Added new payment method options to the StaffOrderModal component
- Added form fields to capture transaction ID, payment date, and notes for manual payments
- Updated the payment processing flow to handle manual payment methods

### Backend Changes

- Added a `payment_details` JSONB column to the `orders` table to store additional payment information
- Updated the OrdersController to accept and process the payment_details parameter
- Updated the Order model to include payment_details in the JSON response

## Data Structure

The `payment_details` field is a JSON object that can contain the following properties:

```json
{
  "payment_method": "clover",
  "transaction_id": "CLV123456789",
  "payment_date": "2025-03-27",
  "staff_id": "user_123",
  "notes": "Payment processed through Clover terminal #2"
}
```

## Usage

1. Staff selects the appropriate payment method in the StaffOrderModal
2. For manual payment methods (Clover, Revel, Other), staff enters:
   - Transaction ID/Reference Number (optional)
   - Payment Date (defaults to today's date)
   - Notes (optional)
3. Staff completes the payment process
4. The system creates an order with the payment details stored in the `payment_details` field

## Reporting

The payment details are included in the order data, allowing for comprehensive reporting on all payment methods, including those processed outside the built-in payment processors.