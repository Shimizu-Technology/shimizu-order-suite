# Phase 4: Service-Level Tenant Isolation

This document describes the implementation of service-level tenant isolation in the Shimizu Order Suite multi-tenant architecture. Service-level isolation ensures that business logic and data processing are properly scoped to the current tenant.

## Overview

Service-level tenant isolation implements the following key principles:

1. **Tenant Context Propagation**: Ensuring tenant context is maintained throughout service calls
2. **Explicit Tenant Filtering**: Adding explicit tenant filtering in service methods
3. **Cross-Tenant Operation Control**: Carefully managing operations that span multiple tenants

## Implementation Details

### TenantContext Module

The `TenantContext` module provides a way to manage tenant context throughout service operations:

```ruby
# app/services/concerns/tenant_context.rb
module TenantContext
  extend ActiveSupport::Concern

  included do
    attr_reader :current_restaurant_id
    
    # Initialize with tenant context
    def initialize(restaurant_id: nil)
      @current_restaurant_id = restaurant_id || Current.restaurant_id
      raise ArgumentError, "Restaurant ID is required" unless @current_restaurant_id.present?
    end
    
    # Run in the context of a specific tenant
    def with_tenant_context(restaurant_id)
      original_restaurant_id = @current_restaurant_id
      @current_restaurant_id = restaurant_id
      
      yield
    ensure
      @current_restaurant_id = original_restaurant_id
    end
    
    # Verify tenant access
    def verify_tenant_access(record)
      return true if record.restaurant_id == @current_restaurant_id
      
      AuditLog.log_security_event(
        Current.user,
        'cross_tenant_access_attempt',
        record.class.name,
        record.id,
        request.remote_ip,
        { attempted_restaurant_id: record.restaurant_id, current_restaurant_id: @current_restaurant_id }
      )
      
      raise SecurityError, "Attempted to access record from another tenant"
    end
  end
end
```

### Service Implementation

All services that handle tenant-specific data include the `TenantContext` concern and apply explicit tenant filtering:

```ruby
# app/services/order_processing_service.rb
class OrderProcessingService
  include TenantContext
  
  def process_order(order)
    # Verify tenant access
    verify_tenant_access(order)
    
    # Process the order
    # ...
  end
  
  def find_orders(criteria)
    # Add explicit tenant filtering
    Order.where(criteria.merge(restaurant_id: current_restaurant_id))
  end
  
  # Super admin method for cross-tenant operations
  def process_all_pending_orders(user)
    raise SecurityError, "Unauthorized access" unless user&.super_admin?
    
    # Process orders across all tenants
    Restaurant.all.each do |restaurant|
      with_tenant_context(restaurant.id) do
        process_pending_orders_for_current_tenant
      end
    end
  end
  
  private
  
  def process_pending_orders_for_current_tenant
    Order.where(status: 'pending', restaurant_id: current_restaurant_id).each do |order|
      process_order(order)
    end
  end
end
```

## Background Job Isolation

Background jobs maintain tenant isolation by capturing and restoring tenant context:

```ruby
# app/jobs/order_notification_job.rb
class OrderNotificationJob < ApplicationJob
  queue_as :default
  
  # Capture tenant context
  def serialize
    super.merge('restaurant_id' => Current.restaurant_id)
  end
  
  # Restore tenant context
  def deserialize(job_data)
    Current.restaurant_id = job_data['restaurant_id']
    super
  end
  
  def perform(order_id)
    # The job runs in the correct tenant context
    order = Order.find(order_id)
    # ...
  end
end
```

## API Client Isolation

External API clients maintain tenant isolation by including tenant context in requests:

```ruby
# app/services/payment_gateway_service.rb
class PaymentGatewayService
  include TenantContext
  
  def process_payment(payment)
    # Verify tenant access
    verify_tenant_access(payment)
    
    # Include tenant ID in API request for audit purposes
    api_client.process_payment(
      amount: payment.amount,
      metadata: { tenant_id: current_restaurant_id }
    )
  end
end
```

## Testing Strategy

Service-level isolation is tested with:

1. **Unit Tests**: Verifying tenant context is maintained
2. **Integration Tests**: Ensuring cross-tenant access is prevented
3. **Background Job Tests**: Confirming tenant context is preserved across job execution

Example test:

```ruby
# Test tenant isolation in OrderProcessingService
test "cannot process orders from another tenant" do
  # Create order for restaurant1
  order = orders(:restaurant1_order)
  
  # Initialize service with restaurant2 context
  service = OrderProcessingService.new(restaurant_id: restaurants(:restaurant2).id)
  
  # Attempt to process order from restaurant1
  assert_raises SecurityError do
    service.process_order(order)
  end
end
```

## Security Considerations

1. **Explicit Tenant Verification**: Always verify tenant ownership before processing
2. **Audit Logging**: Log all cross-tenant access attempts
3. **Super Admin Restrictions**: Carefully control and audit super admin operations

## Best Practices

When implementing tenant-isolated services:

1. Always include the `TenantContext` concern
2. Add explicit tenant filtering in queries
3. Verify tenant access for all input records
4. Use `with_tenant_context` for temporary context changes
5. Capture and restore tenant context in background jobs

## Conclusion

Service-level tenant isolation ensures that business logic respects tenant boundaries, preventing unauthorized cross-tenant operations. By implementing explicit tenant filtering and context propagation, we maintain a strong security boundary at the service layer of our application.
