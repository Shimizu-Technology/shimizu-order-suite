# PostHog Analytics Integration

This document outlines how PostHog analytics is integrated into the Hafaloha application for tracking user behavior, feature usage, and system events.

## Overview

PostHog is an open-source product analytics platform that helps track user behavior across the application. It's integrated in both the frontend (React) and backend (Rails) to provide comprehensive analytics capabilities.

## Configuration

### Environment Variables

The following environment variables are required for PostHog integration:

**Frontend (.env.local):**
```
VITE_PUBLIC_POSTHOG_KEY=phc_8piCP7ZZfApADb2BGOB5zdAeV3Q1EsOptSpEcuZAHPF
VITE_PUBLIC_POSTHOG_HOST=https://us.i.posthog.com
```

**Backend (.env):**
```
POSTHOG_API_KEY=phc_8piCP7ZZfApADb2BGOB5zdAeV3Q1EsOptSpEcuZAHPF
POSTHOG_HOST=https://us.i.posthog.com
```

## Frontend Integration

The frontend integration uses the PostHog React SDK to track user interactions and page views.

### Components

1. **PostHogProvider**: A wrapper component that initializes PostHog and provides context to child components.
   - Located at: `src/shared/components/analytics/PostHogProvider.tsx`
   - Automatically identifies users when they log in
   - Sets up restaurant context for group analytics

2. **Analytics Utilities**: Helper functions for tracking events.
   - Located at: `src/shared/utils/analyticsUtils.ts`
   - Provides consistent event tracking across the application
   - Includes predefined event names for common actions

### Usage in Components

```typescript
import { trackEvent, EventNames } from '../../shared/utils/analyticsUtils';

// In a component
const handleAddToCart = (item) => {
  // Business logic...
  
  // Track the event
  trackEvent(EventNames.ITEM_ADDED_TO_CART, {
    item_id: item.id,
    item_name: item.name,
    price: item.price
  });
};
```

## Backend Integration

The backend integration uses the PostHog Ruby SDK to track server-side events and API usage.

### Components

1. **PostHog Initializer**: Configures the PostHog client.
   - Located at: `config/initializers/posthog.rb`

2. **Analytics Service**: Service object for tracking events with proper context.
   - Located at: `app/services/analytics_service.rb`
   - Handles user and restaurant context
   - Provides methods for tracking events, identifying users, and group analytics

3. **Application Controller Integration**: Automatically tracks controller actions.
   - Adds request tracking to all controllers
   - Filters sensitive parameters

### Usage in Controllers and Models

```ruby
# In a controller
def create
  # Business logic...
  
  # Track a custom event
  analytics.track('order.created', {
    order_id: @order.id,
    total: @order.total,
    items_count: @order.items.count
  })
end
```

## Multi-Tenant Considerations

Since Hafaloha is a multi-tenant application, analytics are structured to support this architecture:

1. **Restaurant Groups**: Each restaurant is set up as a group in PostHog, allowing for:
   - Cross-restaurant analytics for super admins
   - Restaurant-specific analytics for restaurant admins
   - Filtering of events by restaurant

2. **User Identification**: Users are identified with their unique ID and associated with their restaurant.

3. **Event Properties**: All events include restaurant context when applicable.

## Common Events

The application tracks the following key events:

### Customer Events
- Page views
- Menu item views
- Adding items to cart
- Checkout completion
- Reservation creation

### Admin Events
- Menu item creation/updates
- Order processing
- Setting changes
- Inventory management

### System Events
- API performance
- Error tracking
- Feature flag usage

## Feature Flags

PostHog is also used for feature flags, allowing for:
- Gradual rollout of new features
- A/B testing
- Restaurant-specific features

## Best Practices

1. **Consistent Event Naming**: Use the predefined event names in `EventNames` when possible.
2. **Relevant Properties**: Include relevant properties with events for better analysis.
3. **User Privacy**: Avoid tracking personally identifiable information (PII) unless necessary.
4. **Performance**: The SDK batches events to minimize performance impact.

## Debugging

To debug analytics in development:

1. **Frontend**: Open the browser console and look for PostHog debug logs.
2. **Backend**: Set `RAILS_LOG_LEVEL=debug` to see PostHog API calls in the Rails logs.

## PostHog Dashboard

Access the PostHog dashboard at: https://us.i.posthog.com/
