# SMS Notification System

This document describes the SMS notification system used in the Shimizu Order Suite application, including configuration, usage, and troubleshooting.

## Overview

The application uses ClickSend as the SMS provider to send text message notifications to customers for various events:

- Order confirmations
- Order status updates
- Pickup time notifications
- Order ready notifications

## Configuration

### Environment Variables

The following environment variables are required for the SMS functionality:

- `CLICKSEND_USERNAME`: Your ClickSend account username
- `CLICKSEND_API_KEY`: Your ClickSend API key
- `CLICKSEND_APPROVED_SENDER_ID` (optional): A pre-approved sender ID

These variables should be set in your environment or in the `.env` file.

### Restaurant Settings

SMS notifications are controlled per restaurant through the admin settings:

```json
"admin_settings": {
  "notification_channels": {
    "orders": {
      "sms": true,
      "email": true
    }
  },
  "sms_sender_id": "Hafaloha"  // Optional custom sender ID
}
```

- `notification_channels.orders.sms`: Set to `true` to enable SMS notifications for orders
- `sms_sender_id`: Optional custom sender ID (max 11 characters)

## Implementation Details

### Key Components

1. **ClicksendClient**: Service class that handles the actual SMS sending
   - Located at `app/services/clicksend_client.rb`
   - Handles API communication with ClickSend
   - Includes error handling and logging

2. **SendSmsJob**: Background job for asynchronous SMS sending
   - Located at `app/jobs/send_sms_job.rb`
   - Processes SMS sending in the background using Sidekiq

3. **SMS Initializer**: Verifies SMS configuration at startup
   - Located at `config/initializers/sms_client.rb`
   - Checks for required environment variables
   - Logs warnings if configuration is incomplete

### SMS Sending Process

1. The application determines if SMS should be sent based on restaurant settings
2. If enabled, it enqueues a `SendSmsJob` with the message details
3. The job is processed asynchronously by Sidekiq
4. `ClicksendClient` sends the actual API request to ClickSend
5. Results are logged for monitoring and troubleshooting

## Testing SMS Functionality

### Admin Test Endpoint

A dedicated endpoint is available for administrators to test SMS functionality:

```
POST /admin/test_sms
```

#### Using HTTPie:

```bash
http POST http://localhost:3000/admin/test_sms \
  "Authorization: Bearer YOUR_ADMIN_JWT_TOKEN" \
  phone="+16714830219" \
  from="Hafaloha"
```

#### Parameters:

- `phone` (required): The phone number to send the test SMS to (in E.164 format, e.g., +16714830219)
- `from` (optional): The sender ID to use (defaults to "Test" if not provided)

#### Response:

If successful:
```json
{
  "status": "success",
  "message": "Test SMS queued for delivery"
}
```

If failed:
```json
{
  "status": "error",
  "message": "Failed to send test SMS"
}
```

### Checking Logs

SMS sending activity is logged extensively. Look for entries with `[ClicksendClient]` prefix:

```
[ClicksendClient] Attempting to send SMS with params: to=+16714830219, from=Hafaloha, body_length=120
[ClicksendClient] Sending SMS from 'Hafaloha' to '+16714830219'
[ClicksendClient] Sent SMS to +16714830219 - Message ID: 1F00541D-9E4A-6A54-B6DC-C5674125D8F8
```

Error logs will provide details about what went wrong:

```
[ClicksendClient] API Error: code=INVALID_RECIPIENT, message=Invalid recipient, full response=...
```

## Troubleshooting

### Common Issues

1. **SMS not being sent**
   - Check if `notification_channels.orders.sms` is set to `true` in restaurant settings
   - Verify environment variables are set correctly
   - Check application logs for errors

2. **Invalid sender ID**
   - Sender IDs must be 11 characters or less
   - Some countries require pre-approved sender IDs
   - Try using a numeric sender ID (like a phone number) if alphabetic IDs aren't working

3. **Message delivery failures**
   - Check if the recipient's phone number is in E.164 format (e.g., +16714830219)
   - Verify the recipient hasn't blocked messages from short codes or unknown senders
   - Check if there are carrier restrictions in the recipient's region

### Testing with the Admin Endpoint

The admin test endpoint is useful for isolating SMS issues:

1. If the test SMS works but order notifications don't, check the notification settings
2. If the test SMS fails, check the ClickSend credentials and logs for specific error messages

## Best Practices

1. Always use E.164 format for phone numbers (e.g., +16714830219)
2. Keep messages concise to avoid splitting into multiple SMS
3. Include essential information only (order number, status, pickup time)
4. Use a consistent sender ID for better customer recognition
5. Monitor SMS costs and usage to avoid unexpected charges
