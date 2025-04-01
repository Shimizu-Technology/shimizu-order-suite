# Order Notification Consistency

This document describes the solution implemented to fix the issue where previously acknowledged orders would reappear when a user first logs in or clears their cache.

## Problem

The original implementation relied on client-side localStorage to track which orders had been seen by a user. When a user cleared their cache or logged in on a new device, this information was lost, causing all unacknowledged orders from the past 24 hours to be displayed again, even if they had been acknowledged by other admins.

## Solution

The solution implements a hybrid approach that combines server-side tracking with intelligent first-time user handling:

1. **Server-Side User Acknowledgment Tracking**:
   - We already had the `OrderAcknowledgment` model to track which orders have been seen by which users
   - Added a `global_last_acknowledged_at` timestamp to the `Order` model to track when any admin acknowledged an order

2. **First-Time User Experience**:
   - For first-time users or after cache clears, we only show:
     - Orders that have never been acknowledged by any admin
     - OR orders created after the most recent global acknowledgment

3. **Implementation Details**:
   - The server maintains the source of truth about acknowledgment status
   - The client no longer depends on localStorage for tracking seen orders
   - The API intelligently filters orders based on user acknowledgment history

## Changes Made

1. **Database Changes**:
   - Added `global_last_acknowledged_at` column to the `orders` table
   - Created a migration to backfill this field for existing acknowledged orders

### Database Migration Details

Two migrations were created to implement the solution:

```ruby
# Migration to add the global_last_acknowledged_at column
class AddGlobalLastAcknowledgedAtToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :global_last_acknowledged_at, :datetime
    add_index :orders, :global_last_acknowledged_at
  end
end

# Migration to backfill the global_last_acknowledged_at field for existing orders
class BackfillGlobalLastAcknowledgedAt < ActiveRecord::Migration[7.2]
  def up
    # For each order that has at least one acknowledgment,
    # set global_last_acknowledged_at to the earliest acknowledgment time
    execute <<-SQL
      UPDATE orders
      SET global_last_acknowledged_at = (
        SELECT MIN(acknowledged_at)
        FROM order_acknowledgments
        WHERE order_acknowledgments.order_id = orders.id
      )
      WHERE EXISTS (
        SELECT 1
        FROM order_acknowledgments
        WHERE order_acknowledgments.order_id = orders.id
      );
    SQL
  end

  def down
    # This migration is not reversible in a meaningful way
    # since we can't determine which orders had this field set by this migration
    # vs. which ones had it set by the application
  end
end
```

The backfill migration ensures that existing orders that have already been acknowledged won't reappear for first-time users after the fix is deployed.

2. **Backend Changes**:
   - Updated `OrdersController#acknowledge` to set the `global_last_acknowledged_at` field when an order is acknowledged
   - Updated `OrdersController#unacknowledged` to handle first-time users by checking if they have any previous acknowledgments
   - Updated `Order#as_json` to include the `global_last_acknowledged_at` field in the JSON response

### Backend Implementation Details

The key backend changes were made in the `OrdersController` and `Order` model:

```ruby
# In OrdersController#unacknowledged
def unacknowledged
  # Check if this user has any previous acknowledgments
  has_previous_acknowledgments = OrderAcknowledgment.exists?(user_id: current_user.id)

  # Build the query based on whether this is a first-time user
  if has_previous_acknowledgments
    # Regular case: Return orders not acknowledged by this specific user
    unacknowledged_orders = Order.where("created_at > ?", time_threshold)
                                 .where.not(id: current_user.acknowledged_orders.pluck(:id))
                                 .where(staff_created: [false, nil])
                                 .order(created_at: :desc)
  else
    # First-time user case: Only return orders that haven't been acknowledged by anyone
    # OR orders that came in after the last global acknowledgment
    unacknowledged_orders = Order.where("created_at > ?", time_threshold)
                                 .where(staff_created: [false, nil])
                                 .where("global_last_acknowledged_at IS NULL OR created_at > global_last_acknowledged_at")
                                 .order(created_at: :desc)
  end

  render json: unacknowledged_orders, status: :ok
end

# In OrdersController#acknowledge
def acknowledge
  order = Order.find(params[:id])

  # Create acknowledgment record
  acknowledgment = OrderAcknowledgment.find_or_initialize_by(
    order: order,
    user: current_user
  )

  if acknowledgment.new_record? && acknowledgment.save
    # Update the global_last_acknowledged_at timestamp
    order.update(global_last_acknowledged_at: Time.current)
    
    render json: { message: "Order #{order.id} acknowledged" }, status: :ok
  else
    render json: { error: "Failed to acknowledge order" }, status: :unprocessable_entity
  end
end

# In Order model
def as_json(options = {})
  super(options).merge(
    # ... other fields ...
    "global_last_acknowledged_at" => global_last_acknowledged_at&.iso8601
  )
end
```

This ensures that first-time users or users who have cleared their cache only see orders that have never been acknowledged by any admin, or orders that came in after the most recent global acknowledgment.

3. **Frontend Changes**:
   - Removed dependency on localStorage for tracking the last seen order ID
   - Updated the Order interface to include the `global_last_acknowledged_at` field
   - Modified the `displayOrderNotification` function to check if an order has already been acknowledged globally before displaying a notification
   - Updated the code that filters orders to exclude orders that have already been acknowledged globally

### Frontend Implementation Details

The key frontend changes were made in the `AdminDashboard.tsx` component:

```typescript
// In the displayOrderNotification function
const displayOrderNotification = (order: Order) => {
  // Skip displaying notification if the order has already been acknowledged globally
  // This prevents showing notifications for orders that were acknowledged by any admin
  // after a cache clear or first-time login
  if (order.global_last_acknowledged_at) {
    console.log(`[AdminDashboard] Skipping notification for already acknowledged order: ${order.id}`);
    return;
  }
  
  // Rest of the notification display logic...
};

// When filtering orders for notifications
const nonStaffOrders = fetchedOrders.filter(order =>
  !order.staff_created && !order.global_last_acknowledged_at
);
```

This ensures that even if the backend returns orders that have been acknowledged by other admins (which it shouldn't for regular users, but might for first-time users before our fix), the frontend will still filter them out before displaying notifications.

## Deployment Instructions

1. Run the migrations to add the new column and backfill existing data:
   ```
   rails db:migrate
   ```

2. Deploy the updated backend code

3. Deploy the updated frontend code

## Testing

After deployment, test the following scenarios:

1. **Regular User Experience**:
   - Log in as an admin
   - Acknowledge some orders
   - Verify that acknowledged orders don't reappear

2. **First-Time User Experience**:
   - Log in as a new admin or clear browser cache
   - Verify that only truly unacknowledged orders (or orders created after the most recent acknowledgment) appear
   - There should be no flood of old, previously acknowledged notifications

## Additional Notes

The key insight in this fix was that we needed to not only update the server-side logic to handle first-time users correctly, but also ensure that the frontend respects the global acknowledgment status when deciding whether to display notifications. This dual approach ensures consistency across all scenarios.