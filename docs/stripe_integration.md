# Stripe Integration API Documentation

This document provides technical details on the Stripe integration in the Shimizu Order Suite.

## API Endpoints

### Create Payment Intent

**Endpoint:** `POST /stripe/create_intent`

Creates a new Stripe PaymentIntent with the specified amount.

**Request Parameters:**
```json
{
  "amount": "100.00", // Required: Order amount as a string
  "currency": "USD"   // Optional: Currency code (defaults to USD)
}
```

**Response:**
```json
{
  "client_secret": "pi_3NGH...secret_K8Fy" // Client secret for the PaymentIntent
}
```

**Error Response:**
```json
{
  "error": "Stripe payment intent creation failed: [error details]"
}
```

### Capture Payment Intent

**Endpoint:** `POST /stripe/capture_intent`

Captures a previously created Stripe PaymentIntent.

**Request Parameters:**
```json
{
  "intent_id": "pi_3NGHqcHI..." // Required: Stripe PaymentIntent ID to capture
}
```

**Response:**
```json
{
  "status": "succeeded",
  "transaction_id": "pi_3NGHqcHI...",
  "amount": "100.00"
}
```

**Error Response:**
```json
{
  "error": "Stripe capture failed: [error details]"
}
```

## Environment Configuration

The Stripe SDK is configured in `config/initializers/stripe.rb` and uses the following environment variables:

- `STRIPE_PUBLISHABLE_KEY`: Your Stripe publishable key
- `STRIPE_SECRET_KEY`: Your Stripe secret key
- `STRIPE_WEBHOOK_SECRET`: Your Stripe webhook signing secret

These values can be configured through the admin interface or set directly in environment variables.

## Implementation Details

### Stripe Controller

The `StripeController` handles Stripe API interactions and includes:

1. `create_intent`: Initializes a new Stripe PaymentIntent
2. `capture_intent`: Captures a PaymentIntent after confirmation
3. `webhook`: Processes webhook events from Stripe

All endpoints use the Stripe Ruby SDK to interact with Stripe's API.

### Stripe Initialization

The Stripe API is initialized in the `config/initializers/stripe.rb` file:

```ruby
Rails.configuration.stripe = {
  publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'] || Rails.application.credentials.dig(:stripe_publishable_key),
  secret_key: ENV['STRIPE_SECRET_KEY'] || Rails.application.credentials.dig(:stripe_secret_key),
  webhook_secret: ENV['STRIPE_WEBHOOK_SECRET'] || Rails.application.credentials.dig(:stripe_webhook_secret)
}

Stripe.api_key = Rails.configuration.stripe[:secret_key]
```

## Restaurant-specific Configuration

Each restaurant can configure its own Stripe settings through the admin dashboard. These settings are stored in the restaurant's `admin_settings` JSON field:

```ruby
{
  "payment_gateway": {
    "payment_processor": "stripe",
    "test_mode": true,
    "publishable_key": "pk_test_...",
    "secret_key": "sk_test_...",
    "webhook_secret": "whsec_..."
  }
}
```

When processing payments, the system looks up the restaurant's settings to determine which Stripe credentials to use.

## Error Handling

The Stripe controller includes error handling for common API issues:

- Invalid request parameters
- Stripe API errors
- Authentication errors
- Network or connection issues

Errors are logged and appropriate error responses are returned to the client.

## Testing

### Test Mode

In test mode, the Stripe integration can be tested without processing actual payments. Set `test_mode: true` in the admin settings to enable test mode.

### Stripe Test Environment

For more realistic testing, use Stripe's test environment:

1. Create a Stripe account at [stripe.com](https://stripe.com)
2. Use test API keys (prefixed with `pk_test_` and `sk_test_`)
3. Use test credit cards provided by Stripe

### Test Credit Cards

For testing in Stripe's test environment, use these test card numbers:

- Visa: `4242 4242 4242 4242`
- Mastercard: `5555 5555 5555 4444`
- Amex: `3782 822463 10005`

Use any future expiration date and any 3-digit CVV (4-digit for Amex).

## Webhook Integration

Stripe webhooks are used to receive asynchronous payment events:

1. **Setup**: Configure a webhook endpoint in your Stripe dashboard pointing to `/stripe/webhook`
2. **Verification**: Stripe sends a `Stripe-Signature` header that is verified using the webhook secret
3. **Event Handling**: The webhook controller processes events like `payment_intent.succeeded` and updates order status

Example webhook handling code:

```ruby
def webhook
  payload = request.body.read
  sig_header = request.env['HTTP_STRIPE_SIGNATURE']
  
  begin
    event = Stripe::Webhook.construct_event(
      payload, sig_header, webhook_secret
    )
  rescue JSON::ParserError => e
    return render json: { error: 'Invalid payload' }, status: 400
  rescue Stripe::SignatureVerificationError => e
    return render json: { error: 'Invalid signature' }, status: 400
  end
  
  case event.type
  when 'payment_intent.succeeded'
    payment_intent = event.data.object
    # Update order status
    order = Order.find_by(payment_intent_id: payment_intent.id)
    order.update(status: 'paid') if order
  end
  
  render json: { received: true }
end
```

## Security Considerations

- Stripe API keys are stored securely using Rails credentials or environment variables
- HTTPS is required for all Stripe API communications
- PCI compliance is primarily handled by Stripe, as card details never touch your server
- Webhook payloads are verified using signatures to prevent tampering
- Error messages are sanitized to avoid exposing sensitive information

## Debugging

For debugging Stripe API issues, check the Rails logs for detailed error information. Common issues include:

- Invalid credentials
- Malformed requests
- Network connectivity issues
- Stripe service disruptions

The Stripe Dashboard also provides detailed transaction logs and event history for further troubleshooting.
