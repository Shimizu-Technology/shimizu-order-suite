# Menu Item Inventory Tracking System

The Hafaloha API provides a comprehensive inventory tracking system for menu items. This feature allows restaurant owners and staff to monitor stock levels, track damaged items, and automatically update item availability based on current inventory.

## Database Structure

### Menu Items Table
The inventory tracking system extends the `menu_items` table with the following fields:

- `enable_stock_tracking` (boolean, default: false) - Flag to enable/disable inventory tracking
- `stock_quantity` (integer, nullable) - The total quantity of items in stock
- `damaged_quantity` (integer, default: 0) - The quantity of items that have been marked as damaged
- `low_stock_threshold` (integer, default: 10) - The threshold below which an item is considered "low stock"

### Menu Item Stock Audits Table
The system includes a `menu_item_stock_audits` table to maintain a history of all inventory changes:

- `id` (primary key)
- `menu_item_id` (foreign key to menu_items)
- `previous_quantity` (integer) - Stock quantity before the change
- `new_quantity` (integer) - Stock quantity after the change
- `reason` (string) - Description of why the change was made
- `reason_type` (string) - Category of change (e.g., 'restock', 'adjustment', 'damage')
- `created_at` (timestamp) - When the change occurred
- `updated_at` (timestamp) - When the audit record was last updated

## API Endpoints

The inventory tracking system provides several endpoints for managing inventory:

### Update Inventory Settings
`PATCH /menu_items/:id`

Updates a menu item's inventory settings. When inventory tracking is disabled, stock-related fields are automatically cleared.

**Request Body:**
```json
{
  "enable_stock_tracking": true,
  "stock_quantity": 50,
  "damaged_quantity": 2,
  "low_stock_threshold": 10
}
```

### Mark Items as Damaged
`POST /menu_items/:id/mark_damaged`

Records damaged items, updating the damaged_quantity and creating an audit record.

**Request Body:**
```json
{
  "quantity": 3,
  "reason": "Items dropped during delivery"
}
```

### Update Stock Quantity
`POST /menu_items/:id/update_stock`

Updates the stock quantity with a reason and creates an audit record.

**Request Body:**
```json
{
  "stock_quantity": 75,
  "reason_type": "restock",
  "reason_details": "Weekly delivery"
}
```

### Get Stock Audit History
`GET /menu_items/:id/stock_audits`

Returns the complete audit history for a menu item.

## Business Logic

### Stock Status Calculation

The system automatically determines the stock status of menu items based on available quantity:

1. **Available Quantity** = stock_quantity - damaged_quantity

2. **Stock Status** is determined as follows:
   - If available_quantity = 0: "out_of_stock"
   - If available_quantity ≤ low_stock_threshold: "low_stock"
   - Otherwise: "in_stock"

### Order Integration

When orders are processed, the system automatically:

1. Decrements the stock_quantity based on items ordered
2. Creates audit records with reason_type 'order'
3. Updates the stock status based on the new available quantity

## Implementation Considerations

### Performance

- Stock audits are indexed by menu_item_id and created_at for efficient querying
- Stock calculations are performed at the database level where possible

### Data Consistency

- All stock updates are performed in transactions to maintain data integrity
- When inventory tracking is disabled, related fields are explicitly set to default values

## Testing

The inventory system includes comprehensive tests:

- Unit tests for model methods and calculations
- Controller tests for API endpoints
- Integration tests for order processing and inventory updates

## Future Enhancements

- Batch inventory updates for multiple menu items
- Inventory alerts and notifications
- Export of inventory reports
- Integration with supplier ordering systems
