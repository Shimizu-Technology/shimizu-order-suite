# Payment Processing in Shimizu Order Suite

The Shimizu Order Suite platform offers flexible payment processing with support for both PayPal and Stripe integrations. This document provides an overview of the payment system and links to detailed documentation for each payment processor.

## Overview

The payment processing system in Shimizu Order Suite allows restaurant owners to choose between PayPal and Stripe as their payment processor. Key features include:

- Toggle between PayPal and Stripe in the admin settings
- Consistent API for handling payments regardless of the selected processor
- Test mode for simulating payments without processing actual transactions
- Secure handling of payment credentials and transactions

## Payment Gateway Selection

Restaurants can select their preferred payment gateway through the admin settings:

1. Navigate to **Admin → Settings → Payment Gateway**
2. Select either **PayPal** or **Stripe** as the payment processor
3. Enter the appropriate credentials for the selected processor
4. Toggle **Test Mode** as needed for development or testing

The selection is stored in the restaurant's `admin_settings` JSON field:

```json
{
  "payment_gateway": {
    "test_mode": true,
    "payment_processor": "stripe", // or "paypal"
    
    // PayPal fields
    "client_id": "...",
    "client_secret": "...",
    "environment": "sandbox",
    
    // Stripe fields
    "publishable_key": "...",
    "secret_key": "...",
    "webhook_secret": "..."
  }
}
```

## Architecture

The payment system uses a consistent pattern regardless of the selected processor:

1. **Frontend Components**: `PayPalCheckout` and `StripeCheckout` components with a consistent ref-based API
2. **Backend Services**: Payment processing handled by the appropriate service based on restaurant settings
3. **API Endpoints**: Consistent endpoints for creating and capturing payments
4. **Error Handling**: Standardized error responses across payment processors

### Sequence Diagram

```
┌─────────┐          ┌─────────┐          ┌──────────────┐          ┌─────────────────┐
│ Browser │          │ Frontend│          │ Backend API  │          │ Payment Provider│
└────┬────┘          └────┬────┘          └──────┬───────┘          └────────┬────────┘
     │    Load Checkout    │                     │                           │
     │ ──────────────────> │                     │                           │
     │                     │                     │                           │
     │                     │  Get Processor Type │                           │
     │                     │ ──────────────────> │                           │
     │                     │                     │                           │
     │                     │ Return PayPal/Stripe│                           │
     │                     │ <────────────────── │                           │
     │                     │                     │                           │
     │                     │ Load Payment UI     │                           │
     │ <────────────────── │                     │                           │
     │                     │                     │                           │
     │  Submit Payment     │                     │                           │
     │ ──────────────────> │                     │                           │
     │                     │                     │                           │
     │                     │  Create/Capture     │                           │
     │                     │ ──────────────────> │                           │
     │                     │                     │   Process Payment         │
     │                     │                     │ ──────────────────────>   │
     │                     │                     │                           │
     │                     │                     │   Return Result           │
     │                     │                     │ <──────────────────────   │
     │                     │                     │                           │
     │                     │  Return Result      │                           │
     │                     │ <────────────────── │                           │
     │                     │                     │                           │
     │   Show Confirmation │                     │                           │
     │ <────────────────── │                     │                           │
     │                     │                     │                           │
```

## Backend Implementation

The backend handles payment processing through dedicated controllers and services:

- `PaypalController` and `StripeController` for handling API requests
- `PaymentService` for abstracting payment processing logic
- Configuration stored in initializers

### Example Code

```ruby
# In payments_controller.rb
def create
  payment_processor = current_restaurant.admin_settings&.dig('payment_gateway', 'payment_processor') || 'paypal'
  
  if payment_processor == 'stripe'
    result = StripeService.create_payment(params[:amount], params[:currency])
  else
    result = PaypalService.create_payment(params[:amount], params[:currency])
  end
  
  render json: result
end
```

## Test Mode

The system includes a test mode that simulates payments without processing actual transactions:

- Test mode is toggled in the admin settings
- When enabled, the backend simulates successful payments
- The frontend shows test UIs without connecting to actual payment processors
- All test transactions are marked with a "TEST-" prefix in the transaction ID

## Detailed Documentation

For processor-specific details, see:

- [PayPal Integration Documentation](paypal_integration.md)
- [Stripe Integration Documentation](stripe_integration.md)

## Security Considerations

- Payment credentials are never stored in the database
- API keys and secrets are managed through secure environment variables
- All payment communications use HTTPS
- PCI compliance is primarily handled by the payment processors
- The system follows security best practices for handling payment data
