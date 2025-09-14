# Variant System Testing Guide

This guide provides comprehensive testing scenarios for the new variant-level inventory tracking system.

## 🎯 Test Environment Setup

The test scenarios have been automatically created by running:
```bash
rails runner test_variant_system.rb
```

**Test Fundraiser:** "Variant System Test Fundraiser" (slug: `variant-test`)
- **Frontend URL:** `/wholesale/fundraisers/variant-test`
- **Admin URL:** `/admin/wholesale/fundraisers/4/items`

## 📋 Test Scenarios Overview

### 1. No Inventory Tracking (Item #36)
- **Name:** Test Item - No Inventory Tracking
- **Price:** $10.00
- **Stock:** Unlimited
- **Purpose:** Test baseline functionality without inventory constraints

### 2. Basic Item Inventory (Item #37)
- **Name:** Test Item - Basic Item Inventory  
- **Price:** $15.00
- **Stock:** 50 units available
- **Purpose:** Test traditional item-level inventory tracking

### 3. Low Stock Item (Item #38)
- **Name:** Test Item - Low Stock Item
- **Price:** $20.00
- **Stock:** 5 units (below 10-unit threshold)
- **Purpose:** Test low stock warnings and behavior

### 4. Out of Stock Item (Item #39)
- **Name:** Test Item - Out of Stock Item
- **Price:** $25.00
- **Stock:** 0 units available
- **Purpose:** Test out-of-stock handling and error messages

### 5. Option-Level Inventory (Item #40)
- **Name:** Test Item - Option Level Inventory
- **Price:** $18.00 base + size premiums
- **Stock:** Size-based inventory tracking
- **Options:**
  - Small: 20 units ($0 extra)
  - Medium: 15 units (+$2.00)
  - Large: 8 units (+$4.00)
  - X-Large: 3 units (+$6.00) - Low stock
  - XX-Large: 0 units (+$8.00) - Out of stock

### 6. Complex Options (Item #41)
- **Name:** Test Item - Complex Options
- **Price:** $22.00 base + option premiums
- **Stock:** Mixed inventory modes
- **Options:**
  - **Color** (no inventory): Red, Blue, Green, Black
  - **Style** (with inventory):
    - Classic: 30 units ($0)
    - Premium: 15 units (+$5.00)
    - Deluxe: 5 units (+$10.00) - Low stock
    - Limited Edition: 0 units (+$15.00) - Out of stock

### 7. Simple Variant Tracking (Item #42)
- **Name:** Test Item - Variant Tracking Simple
- **Price:** $25.00 base + size premiums
- **Variants:** Size-based variants (4 total)
- **Stock:**
  - S: 25 units ($0)
  - M: 15 units (+$2.00)
  - L: 8 units (+$4.00)
  - XL: 2 units (+$6.00) - Low stock

### 8. Complex Variant Tracking (Item #43)
- **Name:** Test Item - Variant Tracking Complex
- **Price:** $30.00 base + option premiums
- **Variants:** Size × Color combinations (9 total)
- **Stock:**
  - Small, Red: 20 units
  - Small, Blue: 15 units (+$1.00)
  - Small, Green: 10 units (+$2.00)
  - Medium, Red: 12 units (+$3.00)
  - Medium, Blue: 8 units (+$4.00)
  - Medium, Green: 5 units (+$5.00) - Low stock
  - Large, Red: 6 units (+$6.00)
  - Large, Blue: 2 units (+$7.00) - Low stock
  - Large, Green: 0 units (+$8.00) - Out of stock (inactive)

## 🧪 Frontend Testing Checklist

### Basic Functionality
- [ ] **View Fundraiser Page**
  - Navigate to `/wholesale/fundraisers/variant-test`
  - Verify all 8 test items are displayed
  - Check that stock indicators show correctly for each item type

- [ ] **Item Cards**
  - Verify "Add to Cart" buttons work for unlimited items
  - Check stock warnings appear for low stock items
  - Confirm out-of-stock items show appropriate messaging
  - Test quick add functionality respects inventory limits

### Customization Modal Testing

#### No Inventory Tracking (Item #36)
- [ ] Open customization modal
- [ ] Verify no stock limitations or warnings
- [ ] Add multiple quantities without restrictions
- [ ] Confirm price calculations are correct

#### Basic Item Inventory (Item #37)
- [ ] Open customization modal
- [ ] Test quantity selector up to available stock (50)
- [ ] Try to exceed available stock - should be prevented
- [ ] Verify stock display shows "50 available"

#### Low Stock Item (Item #38)
- [ ] Open customization modal
- [ ] Verify low stock warning appears
- [ ] Test quantity limits (max 5)
- [ ] Check stock display shows "5 available (Low Stock)"

#### Out of Stock Item (Item #39)
- [ ] Open customization modal
- [ ] Verify "Out of Stock" message appears
- [ ] Confirm quantity selector is disabled
- [ ] Check "Add to Cart" button is disabled

#### Option-Level Inventory (Item #40)
- [ ] Open customization modal
- [ ] Select each size option and verify:
  - Stock levels display correctly for each size
  - Quantity limits respect individual size stock
  - Low stock warning for X-Large (3 units)
  - Out of stock message for XX-Large
  - Price updates with size premiums

#### Complex Options (Item #41)
- [ ] Open customization modal
- [ ] Test color selection (no inventory impact)
- [ ] Test style selection with inventory:
  - Classic: No restrictions (30 units)
  - Premium: Limited to 15 units
  - Deluxe: Low stock warning (5 units)
  - Limited Edition: Out of stock
- [ ] Verify price updates with both color and style selections

#### Simple Variant Tracking (Item #42)
- [ ] Open customization modal
- [ ] Verify "VARIANT" badge appears
- [ ] Select each size and verify:
  - Individual variant stock displays
  - Quantity limits per variant
  - Low stock warning for XL (2 units)
  - Price updates with size premiums
- [ ] Check variant-specific stock messages

#### Complex Variant Tracking (Item #43)
- [ ] Open customization modal
- [ ] Verify "VARIANT" badge appears
- [ ] Test all size/color combinations:
  - Verify stock levels for each variant
  - Check low stock warnings (Medium+Green, Large+Blue)
  - Confirm Large+Green shows as unavailable
  - Test price calculations with multiple premiums

### Cart Testing

#### Basic Cart Operations
- [ ] Add items of different types to cart
- [ ] Verify cart displays correct inventory tracking badges:
  - "ITEM" for item-level tracking
  - "OPTION" for option-level tracking  
  - "VARIANT" for variant-level tracking
- [ ] Test quantity adjustments in cart
- [ ] Verify stock displays update in real-time

#### Inventory Validation in Cart
- [ ] **Item-Level:** Add basic inventory item, try to increase beyond stock
- [ ] **Option-Level:** Add option inventory item, test quantity limits per option
- [ ] **Variant-Level:** Add variant items, test quantity limits per variant
- [ ] Verify "+" button disables when at max quantity
- [ ] Check stock status messages in cart

#### Auto-Fix Cart Functionality
- [ ] Add items to cart, then reduce stock in admin panel
- [ ] Navigate to checkout to trigger validation
- [ ] Verify auto-fix suggestions appear for:
  - Items that are now out of stock
  - Items with insufficient stock
  - Variants that became inactive
- [ ] Test "Fix Cart Automatically" button
- [ ] Confirm success messages are variant-specific

### Checkout Process
- [ ] **Complete Orders:** Test full checkout for each inventory type
- [ ] **Inventory Reduction:** Verify stock decreases after successful orders
- [ ] **Race Conditions:** Try to place concurrent orders for limited stock items
- [ ] **Validation Errors:** Test checkout with insufficient stock

## 🔧 Admin Testing Checklist

### Item Management
- [ ] **View Items List**
  - Navigate to admin items page
  - Verify all test items display with correct inventory info
  - Check stock status indicators

- [ ] **Edit Items**
  - Open edit modal for each item type
  - Verify inventory tracking toggles work correctly
  - Test switching between tracking modes

### Variant Management
- [ ] **Variant Grid (Items #42, #43)**
  - Open variant management for variant-tracked items
  - Verify grid shows all variants with stock levels
  - Test individual stock quantity updates
  - Check bulk operations (if implemented)

- [ ] **Variant Operations**
  - Update variant stock quantities
  - Toggle variant active/inactive status
  - Test damaged quantity tracking
  - Verify low stock threshold settings

### Inventory Updates
- [ ] **Stock Adjustments**
  - Update stock for item-level inventory
  - Adjust option-level stock quantities
  - Modify variant stock levels
  - Test bulk inventory updates

- [ ] **Audit Trail**
  - Make inventory changes and verify audit records
  - Check audit trail shows:
    - User who made changes
    - Timestamp of changes
    - Previous and new quantities
    - Reason for changes (if provided)

## ⚡ Race Condition Testing

### Concurrent Order Testing
1. **Setup:** Use browser dev tools or multiple browser sessions
2. **Test Scenarios:**
   - [ ] Two users try to order the last item simultaneously
   - [ ] Multiple users order from low stock variants
   - [ ] Admin updates stock while user is in checkout process
   - [ ] Cart validation during concurrent inventory changes

### Database Locking Tests
- [ ] **Variant Stock Updates:** Verify pessimistic locking prevents overselling
- [ ] **Order Processing:** Test inventory reduction during high concurrency
- [ ] **Admin Updates:** Ensure admin changes don't conflict with orders

## 🎭 Edge Case Testing

### Inventory Edge Cases
- [ ] **Zero Stock Handling:** Test behavior when stock reaches exactly 0
- [ ] **Negative Stock Prevention:** Verify system prevents negative inventory
- [ ] **Large Quantities:** Test with very large order quantities
- [ ] **Decimal Quantities:** Ensure system handles integer-only quantities

### Variant Edge Cases
- [ ] **All Variants Out of Stock:** Test item behavior when no variants available
- [ ] **Variant Deactivation:** Test impact of deactivating variants with cart items
- [ ] **Option Changes:** Test impact of modifying options on existing variants
- [ ] **Variant Deletion:** Test cleanup when variants are removed

### User Experience Edge Cases
- [ ] **Slow Network:** Test behavior with slow API responses
- [ ] **Session Timeout:** Test cart persistence across sessions
- [ ] **Browser Refresh:** Test cart state after page refresh
- [ ] **Back Button:** Test navigation behavior in checkout process

## 📊 Performance Testing

### Load Testing
- [ ] **High Traffic:** Test system under high concurrent user load
- [ ] **Large Catalogs:** Test performance with many variants per item
- [ ] **Complex Queries:** Monitor database performance for variant lookups
- [ ] **API Response Times:** Measure response times for variant endpoints

### Database Performance
- [ ] **Query Optimization:** Check for N+1 queries in variant loading
- [ ] **Index Usage:** Verify database indexes are being used effectively
- [ ] **Transaction Performance:** Monitor transaction times for inventory updates

## 🚨 Error Handling Testing

### API Error Scenarios
- [ ] **Network Failures:** Test behavior when API calls fail
- [ ] **Timeout Handling:** Test response to slow API responses
- [ ] **Invalid Data:** Test handling of malformed API responses
- [ ] **Authentication Errors:** Test behavior with expired sessions

### Data Validation
- [ ] **Invalid Quantities:** Test with negative or non-numeric quantities
- [ ] **Missing Options:** Test with incomplete option selections
- [ ] **Invalid Variants:** Test with non-existent variant combinations
- [ ] **Corrupted Cart Data:** Test with malformed cart data

## ✅ Success Criteria

### Functional Requirements
- [ ] All inventory tracking modes work correctly
- [ ] Variant system prevents overselling
- [ ] Real-time stock updates function properly
- [ ] Admin interface allows full variant management
- [ ] Audit trail captures all inventory changes

### Performance Requirements
- [ ] Page load times under 2 seconds
- [ ] API responses under 500ms
- [ ] No N+1 query issues
- [ ] Handles 100+ concurrent users

### User Experience Requirements
- [ ] Intuitive variant selection process
- [ ] Clear stock messaging and warnings
- [ ] Smooth cart and checkout experience
- [ ] Responsive design on mobile devices
- [ ] Accessible interface for screen readers

## 🐛 Bug Reporting

When reporting issues, please include:
1. **Test Scenario:** Which item/variant was being tested
2. **Steps to Reproduce:** Exact steps that led to the issue
3. **Expected Behavior:** What should have happened
4. **Actual Behavior:** What actually happened
5. **Browser/Device:** Browser version and device information
6. **Screenshots/Videos:** Visual evidence of the issue
7. **Console Errors:** Any JavaScript errors in browser console
8. **Server Logs:** Relevant server-side error messages

## 📝 Test Results Template

```
## Test Session: [Date]
**Tester:** [Name]
**Environment:** [Development/Staging/Production]
**Browser:** [Browser and version]

### Frontend Testing Results
- [ ] Basic Functionality: ✅/❌
- [ ] Customization Modals: ✅/❌
- [ ] Cart Operations: ✅/❌
- [ ] Checkout Process: ✅/❌

### Admin Testing Results
- [ ] Item Management: ✅/❌
- [ ] Variant Management: ✅/❌
- [ ] Inventory Updates: ✅/❌
- [ ] Audit Trail: ✅/❌

### Edge Case Testing Results
- [ ] Race Conditions: ✅/❌
- [ ] Error Handling: ✅/❌
- [ ] Performance: ✅/❌

### Issues Found
1. [Issue description with steps to reproduce]
2. [Issue description with steps to reproduce]

### Overall Assessment
[Summary of testing results and recommendations]
```

---

**Happy Testing! 🎉**

Remember to test thoroughly across different browsers, devices, and network conditions to ensure a robust user experience.
