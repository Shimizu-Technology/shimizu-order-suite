# Inventory Tracking System

This document outlines the inventory tracking system implemented for menu items in the Shimizu Order Suite application.

## Overview

The inventory tracking system allows restaurant staff to:

1. Enable/disable inventory tracking for individual menu items
2. Set and maintain stock quantities
3. Mark items as damaged with reasons
4. Set low stock thresholds for automated status changes
5. View an audit history of all inventory changes

## Database Structure

### Menu Items Table

The following fields were added to the `menu_items` table:

- `enable_stock_tracking` (boolean, default: false) - Toggles inventory tracking for a menu item
- `stock_quantity` (integer, nullable) - The total current stock available
- `damaged_quantity` (integer, default: 0) - Items that are damaged/waste and not available for sale
- `low_stock_threshold` (integer, default: 10) - When available stock falls below this number, item is marked as "low stock"

### Menu Item Stock Audits Table

A new table was created to track the history of inventory changes:

- `id` (primary key)
- `menu_item_id` (foreign key to menu_items)
- `previous_quantity` (integer) - Stock quantity before the change
- `new_quantity` (integer) - Stock quantity after the change
- `reason_type` (string) - Type of change (e.g., "restock", "adjustment", "damage", "order")
- `reason` (text) - Detailed reason for the change
- `created_at` (timestamp)
- `updated_at` (timestamp)

## Stock Status Determination

The system automatically determines menu item availability status based on inventory levels:

1. When stock tracking is enabled:
   - Available = stock_quantity - damaged_quantity
   - If Available = 0: "Out of Stock"
   - If Available ≤ low_stock_threshold: "Low Stock"
   - If Available > low_stock_threshold: "In Stock"

2. When stock tracking is disabled:
   - Status is manually set by staff

## API Endpoints

The following endpoints were added to manage inventory:

### Update Inventory Settings

```
PATCH /menu_items/:id
```

Parameters:
- `enable_stock_tracking` (boolean)
- `stock_quantity` (integer)
- `damaged_quantity` (integer)
- `low_stock_threshold` (integer)

### Mark Items as Damaged

```
POST /menu_items/:id/mark_as_damaged
```

Parameters:
- `quantity` (integer) - Number of items to mark as damaged
- `reason` (string) - Reason for marking items as damaged

### Update Stock Quantity

```
POST /menu_items/:id/update_stock
```

Parameters:
- `stock_quantity` (integer) - New total stock quantity
- `reason_type` (string) - Type of update: "restock", "adjustment", "other"
- `reason_details` (string) - Additional details about the update

### Get Stock Audit History

```
GET /menu_items/:id/stock_audits
```

Returns an array of all stock audit records for the specified menu item.

## Integration with Order Processing

When an order is placed:

1. The system checks if ordered items have inventory tracking enabled
2. For tracked items, the stock is decremented by the quantity ordered
3. A stock audit record is created with reason_type "order"
4. If the available quantity falls below the low_stock_threshold, the status is updated accordingly

## Frontend Components

### ItemInventoryModal

A modal component that allows staff to:
- Enable/disable inventory tracking
- Set stock quantities, damaged quantities, and low stock thresholds
- Mark items as damaged with reasons
- Update stock quantities with reasons
- View audit history

### Real-time Updates

The menu item inventory is automatically refreshed when:
- The inventory modal is opened
- Inventory changes are made
- Orders are placed that affect inventory levels

This is done through background polling that refreshes inventory data at regular intervals.

## Performance Considerations

- Stock updates are designed to be lightweight and fast
- Audit records are indexed by menu_item_id for quick retrieval
- Frontend polling is optimized to reduce server load

## Future Improvements

Potential enhancements for the inventory system:
- Batch inventory updates for multiple items
- Scheduled automatic restocking
- Low stock notifications to staff
- Inventory forecasting based on order history
- Integration with supplier ordering systems
