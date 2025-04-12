# User Management in Order Suite

This document outlines the user management system in Order Suite, including user roles, multi-tenant authentication, and special procedures for super_admin users.

## User Roles

Order Suite supports multiple user roles with different permission levels:

- **super_admin**: Global administrators with access to all restaurants and system settings
- **admin**: Restaurant-specific administrators with full access to their restaurant
- **staff**: Restaurant employees with limited access based on assigned permissions
- **customer**: End users who can make reservations and place orders

## Multi-Tenant Authentication

Order Suite implements a multi-tenant authentication system that:

1. Allows the same email to be used across different restaurants
2. Maintains strict email uniqueness within each restaurant
3. Preserves tenant isolation and security boundaries

### Email Uniqueness

- Emails must be unique within each restaurant
- The same email can be used in different restaurants
- This is enforced through a composite unique index on `(email, restaurant_id)`

## Super Admin Users

Super admin users are special global administrators with access to all restaurants and system settings.

### Characteristics of super_admin Users

- Have `role = 'super_admin'`
- Have `restaurant_id = nil` (not associated with any specific restaurant)
- Can access and manage all restaurants in the system
- Can create other super_admin users

### Creating Super Admin Users

For security reasons, super_admin users can only be created through the Rails console. Here's how to create a super_admin:

```ruby
# Connect to Rails console
rails console

# Create a new super_admin user
User.create!(
  email: 'super_admin@example.com',
  password: 'secure_password',
  first_name: 'Super',
  last_name: 'Admin',
  role: 'super_admin',
  restaurant_id: nil,
  phone_verified: true  # Set to true to bypass phone verification
)
```

### Development Environment

In development environments, a default super_admin user is automatically created through the seed data:

- Email: `super_admin@example.com`
- Password: `password123`

You can override these defaults by setting environment variables:
```bash
SUPER_ADMIN_EMAIL=your_email@example.com SUPER_ADMIN_PASSWORD=your_password rails db:seed
```

## User Creation Process

### Regular Users

Regular users (admin, staff, customer) are created through:
- The signup form (customers)
- Admin interface (admin, staff)
- API endpoints (programmatic creation)

All regular users must be associated with a specific restaurant.

### Super Admin Users

Super admin users can only be created through:
- Rails console (as shown above)
- By another super_admin user (if implemented in the admin interface)

## Tenant Isolation

The system enforces strict tenant isolation:
- Regular users can only access data from their associated restaurant
- Super admin users can access data across all restaurants
- Data queries are automatically scoped by restaurant_id

## Best Practices

1. **Super Admin Creation**: Only create super_admin users through the Rails console
2. **Password Security**: Use strong passwords for all users, especially super_admins
3. **Restaurant Association**: Ensure all regular users have a valid restaurant_id
4. **Role Assignment**: Be careful when assigning the super_admin role as it grants global access
