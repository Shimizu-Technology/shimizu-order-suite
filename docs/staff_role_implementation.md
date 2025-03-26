# Staff Role and Order Filtering Implementation

This document describes the implementation of the staff role and order filtering functionality in the Hafaloha application.

## Overview

The implementation adds a new role called "staff" that sits between customer and admin roles. Staff users can only see orders they created, while admins can see all orders and filter by staff.

## Backend Changes

1. **User Model**
   - Added `staff?` method to check if a user has the staff role
   - Added `customer?` method to check if a user has the customer role or no role
   - Added `has_many :created_orders` relationship to track orders created by this user

2. **Order Model**
   - Added `belongs_to :created_by` relationship to track which user created the order

3. **Pundit Policies**
   - Added Pundit for authorization
   - Created `OrderPolicy` to control access to orders based on user role
   - Created `AdminPolicy` to control access to admin features

4. **OrdersController**
   - Updated to use Pundit for authorization
   - Modified to filter orders based on user role
   - Added staff_id parameter for admins to filter orders by staff
   - Updated to set created_by_id when creating orders

## Frontend Changes

1. **Auth Store**
   - Added helper methods for checking roles: `isAdmin()`, `isStaff()`, `isAdminOrStaff()`

2. **Header Component**
   - Updated to show admin dropdown for both admin and staff users
   - Updated mobile menu to show admin options for both admin and staff users

3. **OrderManager Component**
   - Added staff filtering UI for admins
   - Updated to filter orders based on user role

4. **StaffOrderModal**
   - Updated to set the created_by_id when creating orders

5. **OrderStore**
   - Updated the addOrder function to include created_by_id in the payload

## Database Migrations

The following migrations were created:

1. `20250326044040_add_created_by_to_orders.rb`
   - Adds created_by_id column to orders table

2. `20250326044050_update_existing_user_roles.rb`
   - Updates any existing 'employee' roles to 'staff'

3. `20250326050013_update_existing_orders_created_by.rb`
   - Sets created_by_id for existing orders to a default admin user

## How to Run Migrations

```bash
cd hafaloha_api
bundle exec rails db:migrate
```

## Testing

1. **Admin Users**
   - Should be able to see all orders
   - Should be able to filter orders by staff

2. **Staff Users**
   - Should only be able to see orders they created
   - Should be able to access admin routes

3. **Customer Users**
   - Should only be able to see their own orders
   - Should not be able to access admin routes