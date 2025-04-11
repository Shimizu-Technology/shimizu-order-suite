# Multi-Tenant Code Review Guidelines

This document provides guidelines for reviewing code changes in the Shimizu Order Suite multi-tenant architecture. Following these guidelines will help ensure that all code changes maintain proper tenant isolation and security.

## General Principles

1. **Default to Tenant Isolation**: All data access should be scoped to the current tenant by default.
2. **Explicit Global Access**: Any code that needs to access data across tenants must explicitly justify this need.
3. **Security First**: Always prioritize tenant isolation over convenience or performance optimizations.
4. **Audit Everything**: Security-sensitive operations should be logged for audit purposes.

## Code Review Checklist

### Models

- [ ] Does the model include the `TenantScoped` concern if it contains tenant-specific data?
- [ ] Are all associations properly scoped to respect tenant boundaries?
- [ ] Are there appropriate validations to ensure tenant_id is present where required?
- [ ] Do any custom scopes or queries respect tenant isolation?
- [ ] Are there any raw SQL queries that might bypass tenant scoping?

### Controllers

- [ ] Does the controller include the `TenantIsolation` concern?
- [ ] Are there any overrides of `global_access_permitted?` that might bypass tenant isolation?
- [ ] Does the controller properly validate tenant context before processing requests?
- [ ] Are there appropriate audit logs for security-sensitive operations?
- [ ] Is rate limiting applied appropriately for tenant-specific endpoints?

### Services

- [ ] Does the service explicitly handle tenant context?
- [ ] Are there any operations that might leak data across tenant boundaries?
- [ ] Is tenant context properly maintained when making external API calls?
- [ ] Are background jobs properly scoped to the tenant context?

### Authentication & Authorization

- [ ] Do JWT tokens include the restaurant_id claim?
- [ ] Is the restaurant_id validated during token verification?
- [ ] Are there appropriate checks to ensure users can only access their own restaurant's data?
- [ ] Are super admin privileges properly restricted and audited?

### Database Operations

- [ ] Are there any migrations that might affect tenant isolation?
- [ ] Do new tables have appropriate foreign key constraints to the restaurants table?
- [ ] Are NOT NULL constraints applied to restaurant_id columns where appropriate?
- [ ] Are there any database triggers or functions that might bypass tenant isolation?

### Frontend Considerations

- [ ] Does the frontend properly include restaurant_id in API requests?
- [ ] Are there any UI elements that might expose data from other tenants?
- [ ] Is tenant context properly maintained during user navigation?

## Common Pitfalls

### Bypassing Tenant Isolation

```ruby
# BAD: This bypasses tenant isolation
users = User.all

# GOOD: This respects tenant isolation
users = User.with_restaurant_scope
```

### Hardcoding Restaurant IDs

```ruby
# BAD: Hardcoding restaurant IDs
users = User.where(restaurant_id: 1)

# GOOD: Using the current tenant context
users = User.where(restaurant_id: current_restaurant.id)
```

### Global Queries in Background Jobs

```ruby
# BAD: No tenant context in background job
def perform(user_id)
  user = User.find(user_id)
  # Operations without tenant context
end

# GOOD: Maintaining tenant context in background job
def perform(user_id, restaurant_id)
  ActiveRecord::Base.current_restaurant = Restaurant.find(restaurant_id)
  user = User.find(user_id)
  # Operations with tenant context
  ensure
    ActiveRecord::Base.current_restaurant = nil
end
```

## Review Process

1. **Automated Checks**: Run the tenant isolation test suite to catch common issues.
2. **Manual Review**: Use this checklist during code review to identify potential issues.
3. **Security Review**: For significant changes, request a dedicated security review.
4. **Post-Deployment Verification**: After deployment, verify tenant isolation with production data.

## Reporting Issues

If you discover a tenant isolation issue during code review:

1. Mark the PR as "Needs Fixes" with a clear explanation of the issue.
2. Reference the specific guideline from this document that is being violated.
3. Suggest a solution that maintains proper tenant isolation.
4. For critical security issues, notify the security team immediately.

By following these guidelines, we can ensure that the Shimizu Order Suite maintains strong tenant isolation and security as the codebase evolves.
