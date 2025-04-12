# Order Numbering System

## Overview

The Order Numbering System provides a restaurant-specific, human-readable order identification system that replaces the default database ID-based order numbers. This system ensures that each restaurant has its own unique order numbering sequence that is more intuitive and user-friendly than raw database IDs.

## Key Features

- **Restaurant-specific order numbers**: Each restaurant has its own sequence of order numbers
- **Simple, readable format**: Order numbers follow the format `[PREFIX][COUNTER]` (e.g., "ST001")
- **Daily counter reset**: Order counters can reset daily to maintain a clean, consistent numbering pattern
- **Backward compatibility**: Existing orders without custom order numbers continue to display their database IDs
- **Multi-tenant isolation**: Order numbers are unique within each restaurant's context

## Implementation Details

### Database Structure

The system relies on two main database tables:

1. **restaurant_counters**: Stores counter information for each restaurant
   - `restaurant_id`: The restaurant this counter belongs to
   - `daily_order_counter`: Counter that resets daily
   - `total_order_counter`: Running total counter (never resets)
   - `last_reset_date`: Date when the counter was last reset

2. **orders.order_number**: Column added to the orders table to store the generated order number

### Order Number Generation

Order numbers are generated using the following process:

1. A restaurant-specific prefix is derived from the first 2-3 letters of the restaurant's name
2. The daily counter is incremented
3. The counter is formatted as a 3-digit zero-padded number (e.g., "001")
4. The prefix and counter are combined to create the final order number (e.g., "ST001")

```ruby
# Example order number generation
def generate_order_number
  reset_daily_counter_if_needed
  restaurant_prefix = get_restaurant_prefix
  
  self.daily_order_counter += 1
  self.total_order_counter += 1
  
  counter_str = daily_order_counter.to_s.rjust(3, '0')
  
  order_number = "#{restaurant_prefix}#{counter_str}"
  save!
  order_number
end
```

### Daily Counter Reset

The system can optionally reset the daily counter at the beginning of each day:

```ruby
def reset_daily_counter_if_needed
  current_date = Date.current
  if last_reset_date < current_date
    self.daily_order_counter = 0
    self.last_reset_date = current_date
  end
end
```

### Integration with Orders

The `Order` model assigns an order number before creation:

```ruby
def assign_order_number
  return if order_number.present?
  self.order_number = RestaurantCounter.next_order_number(restaurant_id)
end
```

## Frontend Display

The order number is displayed in place of the database ID throughout the application:

- Order history views
- Order detail modals
- Admin dashboards
- Staff transaction records
- Receipts and confirmations

## House Account Integration

When orders are charged to staff house accounts, the order number is stored in the transaction record and displayed in transaction history:

```ruby
def charge_order_to_house_account(order, created_by = nil)
  # Use order_number if available, otherwise fall back to id
  order_identifier = order.order_number.present? ? order.order_number : order.id.to_s
  add_house_account_transaction(
    order.total,
    'order',
    "Order ##{order_identifier}",
    order,
    created_by
  )
end
```

## Maintenance Considerations

- **Prefix Collisions**: If two restaurants have similar names, their prefixes might be similar. Consider implementing a more robust prefix generation algorithm if this becomes an issue.
- **Counter Overflow**: The system uses a 3-digit counter, which allows for up to 999 orders per day. If a restaurant exceeds this number, consider increasing the digit count.
- **Migration**: When migrating existing orders to use the new numbering system, be careful to maintain uniqueness and avoid conflicts.

## Future Improvements

- Add configuration options for order number format
- Implement more robust prefix generation
- Add order number validation
- Create migration strategy for existing orders
