# PayPal Integration API Documentation

This document provides technical details on the PayPal Advanced/Expanded Checkout integration in the Hafaloha API.

## API Endpoints

### Create Order

**Endpoint:** `POST /paypal/create_order`

Creates a new PayPal order with the specified amount.

**Request Parameters:**
```json
{
  "amount": "100.00" // Required: Order amount as a string
}
```

**Response:**
```json
{
  "orderId": "5O190127TN364715T" // PayPal order ID
}
```

**Error Response:**
```json
{
  "error": "PayPal order creation failed: [error details]"
}
```

### Capture Order

**Endpoint:** `POST /paypal/capture_order`

Captures a previously created PayPal order after customer approval.

**Request Parameters:**
```json
{
  "orderID": "5O190127TN364715T" // Required: PayPal order ID to capture
}
```

**Response:**
```json
{
  "status": "COMPLETED",
  "transaction_id": "3RM92092L5168622X",
  "amount": "100.00"
}
```

**Error Response:**
```json
{
  "error": "PayPal capture failed: [error details]"
}
```

## Environment Configuration

The PayPal SDK is configured in `config/initializers/paypal.rb` and uses the following environment variables:

- `PAYPAL_CLIENT_ID`: Your PayPal client ID
- `PAYPAL_CLIENT_SECRET`: Your PayPal client secret
- `PAYPAL_ENVIRONMENT`: Set to either "sandbox" or "production"

These values can be configured through the admin interface or set directly in environment variables.

## Implementation Details

### PayPal Controller

The `PaypalController` handles PayPal API interactions and includes:

1. `create_order`: Initializes a new PayPal order
2. `capture_order`: Completes payment for an approved order

Both endpoints use the PayPal Checkout SDK to interact with PayPal's API.

### PayPal Helper

The `PaypalHelper` module manages PayPal environment configuration and client setup:

```ruby
module PaypalHelper
  def self.environment
    if Rails.env.production? && ENV['PAYPAL_ENVIRONMENT'] == 'production'
      # Production environment
      PayPal::LiveEnvironment.new(ENV['PAYPAL_CLIENT_ID'], ENV['PAYPAL_CLIENT_SECRET'])
    else
      # Sandbox environment for development and testing
      PayPal::SandboxEnvironment.new(ENV['PAYPAL_CLIENT_ID'] || 'sandbox-client-id', 
                                    ENV['PAYPAL_CLIENT_SECRET'] || 'sandbox-client-secret')
    end
  end

  def self.client
    PayPal::PayPalHttpClient.new(environment)
  end
end
```

## Error Handling

The PayPal controller includes error handling for common API issues:

- Invalid request parameters
- PayPal API errors
- Network or connection issues

Errors are logged and appropriate error responses are returned to the client.

## Testing

### Test Environment

In test mode, the PayPal integration can be tested without processing actual payments. Set `test_mode: true` in the admin settings to enable test mode.

### Sandbox Testing

For more realistic testing, use PayPal's Sandbox environment:

1. Create a sandbox account at [developer.paypal.com](https://developer.paypal.com)
2. Create test business and personal accounts
3. Use sandbox credentials in your development environment
4. Use test credit cards provided by PayPal for sandbox testing

## Security Considerations

- PayPal API credentials are stored securely using Rails credentials or environment variables
- HTTPS is required for all PayPal API communications
- PCI compliance is handled by PayPal, as card details never touch your server
- Error messages are sanitized to avoid exposing sensitive information

## Debugging

For debugging PayPal API issues, check the Rails logs for detailed error information from the PayPal SDK. Common issues include:

- Invalid credentials
- Malformed requests
- Network connectivity issues
- PayPal service disruptions

The PayPal Dashboard also provides detailed transaction logs for further troubleshooting.
