# Payment Integration with Braintree/PayPal

This document outlines how the payment integration with Braintree/PayPal works in the Shimizu Order Suite application.

## Overview

The Shimizu Order Suite application uses Braintree as the payment gateway, which also supports PayPal payments. The integration follows a client-server model:

1. The client (frontend) requests a client token from the server
2. The client uses this token to initialize the Braintree SDK
3. The client collects payment information and gets a payment method nonce
4. The client sends this nonce to the server to process the payment
5. The server processes the payment and returns the result

## Backend Components

### Configuration

- **Braintree Initializer**: Located at `config/initializers/braintree.rb`, this file loads the Braintree gem.
- **Payment Service**: Located at `app/services/payment_service.rb`, this service handles all Braintree operations including generating client tokens, processing payments, and retrieving transaction details.
- **Payments Controller**: Located at `app/controllers/payments_controller.rb`, this controller exposes the payment API endpoints.

### API Endpoints

- **GET /payments/client_token**: Generates a client token for initializing the Braintree SDK on the frontend.
- **POST /payments/process**: Processes a payment using a payment method nonce.
- **GET /payments/transaction/:id**: Retrieves details about a specific transaction.

### Database Fields

The `orders` table has been updated with the following fields to store payment information:

- `payment_method`: The payment method used (e.g., 'credit_card', 'paypal')
- `transaction_id`: The Braintree transaction ID
- `payment_status`: The status of the payment (e.g., 'pending', 'completed', 'failed')
- `payment_amount`: The amount that was paid

## Frontend Components

### API Client

The frontend API client for payments is located at `src/shared/api/endpoints/payments.ts` and provides methods for:

- Getting a client token
- Processing a payment
- Retrieving transaction details

### Admin Settings

The admin can configure payment settings in the admin dashboard under the "Payments" tab. This includes:

- Enabling/disabling test mode
- Setting Braintree credentials (merchant ID, public key, private key)
- Choosing the environment (sandbox or production)

## Test Mode

The application supports a test mode that allows orders to be created without actual payment processing. This is useful for testing the ordering flow without real payments.

When test mode is enabled:
- The payment service returns a simulated successful response
- The transaction ID is prefixed with "TEST-"
- No actual payment processing occurs

## Production Setup

To use the payment integration in production:

1. Create a Braintree account at [braintreepayments.com](https://www.braintreepayments.com/)
2. Get your production credentials (merchant ID, public key, private key)
3. Enter these credentials in the admin dashboard
4. Set the environment to "production"
5. Disable test mode

## Troubleshooting

If you encounter issues with the payment integration:

1. Check that the Braintree credentials are correct
2. Verify that the environment (sandbox/production) is set correctly
3. Check the server logs for any errors
4. Ensure that the Braintree account is properly configured

## Security Considerations

- Braintree credentials are stored in the restaurant's `admin_settings` JSON field
- The frontend never directly handles credit card information
- All payment processing happens on the server side
- The client token has a limited lifespan and is tied to a specific merchant account
