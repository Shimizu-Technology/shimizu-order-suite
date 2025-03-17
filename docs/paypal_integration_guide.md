# PayPal Integration Guide

This guide explains how to set up and configure PayPal for your Hafaloha application.

## Prerequisites

1. A PayPal Business account
2. Access to the [PayPal Developer Dashboard](https://developer.paypal.com/dashboard/)

## Setup Steps

### 1. Create a PayPal App

1. Log in to the [PayPal Developer Dashboard](https://developer.paypal.com/dashboard/)
2. Navigate to "My Apps & Credentials"
3. Click "Create App" under the REST API apps section
4. Enter a name for your app (e.g., "Hafaloha")
5. Select "Merchant" as the app type
6. Click "Create App"

### 2. Get API Credentials

After creating your app, you'll be taken to the app details page. Here you can find your API credentials:

1. **Client ID**: This is your public identifier for the PayPal API
2. **Secret**: This is your private key for the PayPal API

You'll need to enter these credentials in the Hafaloha admin settings.

### 3. Configure Webhooks

Webhooks allow PayPal to notify your application about payment events in real-time.

1. In your app details page, scroll down to the "Webhooks" section
2. Click "Add Webhook"
3. Enter your webhook URL:
   - For production: `https://your-api-domain.com/paypal/webhook`
   - For testing: `https://your-test-domain.com/paypal/webhook`
4. Select the following event types:
   - `PAYMENT.CAPTURE.COMPLETED`
   - `PAYMENT.CAPTURE.DENIED`
   - `PAYMENT.CAPTURE.PENDING`
   - `PAYMENT.CAPTURE.REFUNDED`
   - `PAYMENT.CAPTURE.REVERSED`
   - `CHECKOUT.ORDER.APPROVED`
   - `CHECKOUT.ORDER.COMPLETED`
   - `CHECKOUT.ORDER.DECLINED`
   - `PAYMENT.REFUND.COMPLETED`
   - `PAYMENT.REFUND.FAILED`
   - `CUSTOMER.DISPUTE.CREATED`
   - `CUSTOMER.DISPUTE.RESOLVED`
   - `CUSTOMER.DISPUTE.UPDATED`
5. Click "Save"
6. After saving, you'll see your webhook details including the **Webhook ID**
7. Copy the **Webhook ID** as you'll need it for the Hafaloha admin settings

#### How PayPal Webhook Verification Works

PayPal uses a different approach than Stripe for webhook verification:

1. PayPal includes several HTTP headers in each webhook notification:
   - `PAYPAL-TRANSMISSION-ID`: A unique identifier for the transmission
   - `PAYPAL-TRANSMISSION-TIME`: The timestamp of when the notification was sent
   - `PAYPAL-TRANSMISSION-SIG`: The actual signature of the transmission
   - `PAYPAL-CERT-URL`: The URL to PayPal's public certificate
   - `PAYPAL-AUTH-ALGO`: The algorithm used to generate the signature

2. Our application uses these headers along with the **Webhook ID** to verify that the webhook notification is authentic and hasn't been tampered with.

3. Unlike Stripe, PayPal doesn't use a "Webhook Secret" - instead, the **Webhook ID** is the key piece of information needed for verification.

### 4. Configure Hafaloha Admin Settings

1. Log in to your Hafaloha admin dashboard
2. Navigate to "Settings" > "Payment Gateway"
3. Select "PayPal" as the payment processor
4. Fill in the following fields:
   - **Client ID**: Your PayPal app client ID
   - **Client Secret**: Your PayPal app secret
   - **Environment**: Select "Sandbox" for testing or "Production" for live payments
   - **Webhook ID**: The ID of the webhook you created in step 3 (this is used for webhook verification)
5. Toggle "Test Mode" on or off as needed
   - When "Test Mode" is on, no real payments will be processed
   - Use "Test Mode" for testing your integration
6. Click "Save Settings"

## Testing Your Integration

### Sandbox Testing

1. Make sure "Test Mode" is enabled in your admin settings
2. Use the [PayPal Sandbox test accounts](https://developer.paypal.com/dashboard/accounts) to simulate payments
3. Create a test order in your Hafaloha application
4. Complete the payment using a sandbox account
5. Verify that the order status is updated correctly

### Webhook Testing

1. In the PayPal Developer Dashboard, go to your app details
2. Scroll down to the "Webhooks" section
3. Click on your webhook
4. Click "Test" to simulate webhook events
5. Select an event type (e.g., `PAYMENT.CAPTURE.COMPLETED`)
6. Click "Send Test"
7. Check your application logs to verify that the webhook was received and processed correctly

## Going Live

When you're ready to accept real payments:

1. Update your webhook URL to your production domain
2. Set "Environment" to "Production" in your admin settings
3. Turn off "Test Mode"
4. Test a real payment with a small amount to ensure everything is working correctly

## Troubleshooting

### Common Issues

1. **Webhook not received**: Check that your webhook URL is publicly accessible and that your server is properly configured to receive POST requests.

2. **Payment not processed**: Verify that your Client ID and Secret are correct and that you're using the right environment (Sandbox or Production).

3. **Order status not updated**: Check your application logs for any errors in processing webhook events.

### Logging

The PayPal integration logs important events to your application logs. Check these logs for any errors or warnings related to PayPal payments.

## Additional Resources

- [PayPal Developer Documentation](https://developer.paypal.com/docs/api/overview/)
- [PayPal REST API Reference](https://developer.paypal.com/api/rest/)
- [PayPal Webhooks Documentation](https://developer.paypal.com/api/rest/webhooks/)
