# Notification System Documentation

## Overview

The Hafaloha notification system is designed to be flexible and support multiple frontends. It allows for customized notification templates based on:

1. **Restaurant** - Each restaurant can have its own templates
2. **Frontend** - Different frontends (e.g., Hafaloha, Sushi Spot) can have their own templates
3. **Notification Type** - Different types of notifications (e.g., order confirmation, reservation confirmation)
4. **Channel** - Different channels (email, SMS, WhatsApp) can have different templates

## Key Components

### NotificationTemplate Model

The `NotificationTemplate` model stores templates for different notification types and channels. Each template can be associated with a specific restaurant and frontend.

Key fields:
- `notification_type`: The type of notification (e.g., order_confirmation, reservation_confirmation)
- `channel`: The channel to send the notification through (email, sms, whatsapp)
- `subject`: The subject line for email notifications
- `content`: The content of the notification
- `sender_name`: The name of the sender
- `restaurant_id`: The ID of the restaurant (null for default templates)
- `frontend_id`: The ID of the frontend (null for default templates)
- `active`: Whether the template is active

### NotificationService

The `NotificationService` is responsible for sending notifications. It:

1. Finds the appropriate template based on notification type, channel, restaurant, and frontend
2. Renders the template with the provided data
3. Sends the notification through the appropriate channel

### TemplateRenderer

The `TemplateRenderer` is responsible for rendering templates with variables. It supports:

1. Variable substitution (e.g., `{{ customer_name }}`)
2. Conditional blocks (e.g., `{% if variable_name %} content {% endif %}`)

## Frontend-Specific Templates

The system supports frontend-specific templates through the `frontend_id` field. This allows different frontends to have their own templates with their own styling and branding.

### Template Lookup Order

When looking for a template, the system follows this order:

1. Restaurant-specific template for the specified frontend
2. Restaurant-specific template without a frontend specified
3. Default template for the specified frontend
4. Default template without a frontend specified

### Frontend-Specific Data

The system also supports frontend-specific data in templates. This includes:

- `brand_color`: The primary brand color for the frontend
- `logo_url`: The URL of the logo for the frontend
- `footer_text`: The footer text for the frontend

## Admin UI

The admin UI allows restaurant administrators to:

1. Select which frontend to use for their restaurant
2. Customize notification templates for their restaurant
3. Preview templates with sample data

## Adding a New Frontend

To add a new frontend:

1. Add the frontend ID to the frontend options in the RestaurantSettings component
2. Add frontend-specific data to the NotificationService's `add_frontend_specific_data` method
3. Create default templates for the new frontend

## Example Usage

```ruby
# Send an order confirmation notification
NotificationService.send_notification(
  'order_confirmation',
  { email: 'customer@example.com', phone: '+1234567890' },
  {
    restaurant_id: 1,
    frontend_id: 'hafaloha',
    customer_name: 'John Doe',
    order_id: '12345',
    total: '45.99',
    items: '1x Aloha Poke, 2x Spam Musubi'
  }
)
```

## Best Practices

1. Always include all required variables in templates
2. Use conditional blocks for optional content
3. Test templates with sample data before deploying
4. Create default templates for all notification types and channels
5. Use frontend-specific styling for a consistent brand experience
