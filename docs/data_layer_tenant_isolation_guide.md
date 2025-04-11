# Phase 3: Model-Level Tenant Isolation

This document describes the implementation of model-level tenant isolation in the Shimizu Order Suite multi-tenant architecture. Model-level isolation ensures that data access is properly scoped to the current tenant at the data layer, providing a critical security boundary.

## Overview

Model-level tenant isolation implements the following key principles:

1. **Default Tenant Scoping**: All queries automatically filter by the current tenant
2. **Validation of Tenant Ownership**: Ensures records belong to the correct tenant
3. **Prevention of Tenant ID Tampering**: Protects against malicious attempts to access other tenants' data

## Implementation Details

### TenantScoping Concern

The `TenantScoping` concern is the core component of our model-level isolation strategy. It provides:

- Default scopes that automatically filter queries by the current tenant
- Callbacks to set the tenant ID on new records
- Validation to ensure records belong to the correct tenant

```ruby
# app/models/concerns/tenant_scoping.rb
module TenantScoping
  extend ActiveSupport::Concern

  included do
    # Default scope to filter by current tenant
    default_scope -> { where(restaurant_id: Current.restaurant_id) if Current.restaurant_id.present? }
    
    # Set tenant ID before validation
    before_validation :set_tenant_id, if: :new_record?
    
    # Validate tenant ID
    validate :validate_tenant_id, if: -> { restaurant_id.present? }
    
    # Prevent changing tenant ID
    attr_readonly :restaurant_id, if: :persisted?
  end

  private

  def set_tenant_id
    self.restaurant_id ||= Current.restaurant_id if Current.restaurant_id.present?
  end

  def validate_tenant_id
    if Current.restaurant_id.present? && restaurant_id != Current.restaurant_id
      errors.add(:restaurant_id, "must match the current tenant")
    end
  end
end
```

### Application to Models

The `TenantScoping` concern has been applied to all tenant-specific models:

```ruby
class MenuItem < ApplicationRecord
  include TenantScoping
  
  # Rest of the model code...
end
```

### Unscoped Queries

In certain admin-level operations, we need to query across tenants. This is done using the `unscoped` method, which is carefully restricted to super admin contexts:

```ruby
# Only for super admin operations
def all_restaurants_report
  raise SecurityError, "Unauthorized access" unless Current.user&.super_admin?
  
  # Unscoped query to access all tenants
  Restaurant.unscoped.all
end
```

## Database-Level Constraints

In addition to model-level isolation, we've implemented database-level constraints:

1. **NOT NULL Constraints**: Ensuring tenant ID is always present
2. **Foreign Key Constraints**: Maintaining referential integrity within a tenant
3. **Check Constraints**: Preventing invalid tenant IDs

```sql
-- Example migration for adding constraints
ALTER TABLE menu_items 
  ALTER COLUMN restaurant_id SET NOT NULL,
  ADD CONSTRAINT fk_menu_items_restaurants 
    FOREIGN KEY (restaurant_id) 
    REFERENCES restaurants(id);
```

## Testing Strategy

Model-level isolation is tested with:

1. **Unit Tests**: Verifying tenant scoping behavior
2. **Integration Tests**: Ensuring cross-tenant access is prevented
3. **Security Tests**: Attempting to bypass tenant isolation

Example test:

```ruby
# Test tenant isolation in MenuItem model
test "cannot access menu items from another tenant" do
  # Set current tenant
  Current.restaurant_id = restaurants(:restaurant1).id
  
  # Create item for current tenant
  item1 = MenuItem.create!(name: "Test Item 1")
  
  # Switch tenant
  Current.restaurant_id = restaurants(:restaurant2).id
  
  # Create item for second tenant
  item2 = MenuItem.create!(name: "Test Item 2")
  
  # Verify each tenant only sees their own items
  assert_includes MenuItem.all, item2
  assert_not_includes MenuItem.all, item1
end
```

## Security Considerations

1. **Avoiding Tenant ID Exposure**: We never expose tenant IDs in public APIs
2. **Preventing Mass Assignment**: Tenant IDs are protected from mass assignment
3. **Logging Suspicious Activity**: Any attempt to access cross-tenant data is logged and alerted

## Best Practices

When working with tenant-scoped models:

1. Always use the model's interface rather than direct SQL queries
2. Never use `unscoped` without explicit super admin authorization
3. Add explicit tenant filtering in complex queries for clarity
4. Use transactions to ensure data consistency within a tenant

## Conclusion

Model-level tenant isolation provides a robust security boundary that prevents unauthorized access to tenant data. By implementing both application-level and database-level constraints, we ensure that tenant isolation is enforced at multiple layers of the application stack.
