# Pundit Authorization System

This document provides an overview of the Pundit-based authorization system in Shimizu Order Suite, explaining how policy classes are used to implement fine-grained access control.

## Overview

Shimizu Order Suite uses the Pundit gem to implement a comprehensive policy-based authorization system. This approach provides several benefits:

1. **Centralized Authorization Logic**: All authorization rules are defined in policy classes, making them easy to maintain and update
2. **Fine-grained Access Control**: Permissions can be defined at the action level for each resource
3. **Context-aware Authorization**: Policies can consider both the user's role and their relationship to the resource
4. **Automatic Query Scoping**: Database queries are automatically filtered based on the user's permissions

## Role System

Shimizu Order Suite implements a tiered role system with four distinct roles:

1. **Super Admin**: Platform administrators with complete system access
2. **Admin**: Restaurant managers with broad administrative access
3. **Staff**: Regular employees with limited administrative access
4. **Customer**: End users with access only to customer-facing features

Each role has progressively more permissions, with helper methods in the User model to simplify role checks:

```ruby
# app/models/user.rb
def super_admin?
  role == "super_admin"
end

def admin?
  role == "admin"
end

def staff?
  role == "staff"
end

def customer?
  role == "customer"
end

def admin_or_above?
  role.in?(["admin", "super_admin"])
end

def staff_or_above?
  role.in?(["staff", "admin", "super_admin"])
end
```

## Policy Structure

### Base Policy

All policies inherit from the ApplicationPolicy class, which provides common functionality:

```ruby
# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end
  
  # Role-based helper methods
  def super_admin?
    user && user.super_admin?
  end
  
  def admin?
    user && user.admin?
  end
  
  def staff?
    user && user.staff?
  end
  
  def admin_or_above?
    user && user.admin_or_above?
  end
  
  def staff_or_above?
    user && user.staff_or_above?
  end

  # Default permissions (deny by default)
  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def update?
    false
  end

  def destroy?
    false
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope
  end
end
```

### Resource-specific Policies

Each resource type has its own policy class that defines permissions based on the user's role and relationship to the resource.

#### Order Policy

The Order policy controls who can view, create, update, and manage orders:

```ruby
# app/policies/order_policy.rb
class OrderPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.admin_or_above?
        # Admins and super admins can see all orders
        scope.all
      elsif user.staff? && user.staff_member.present?
        # Staff can see orders they created AND customer orders
        staff_id = user.staff_member.id
        
        # Staff can see orders they created OR customer orders
        # Customer orders are identified by staff_created: false AND is_staff_order: false
        scope.where(
          "(created_by_staff_id = :staff_id) OR (staff_created = :is_customer_created AND is_staff_order = :is_customer_order)", 
          staff_id: staff_id, 
          is_customer_created: false,
          is_customer_order: false
        )
      else
        # Regular customers can only see their own orders
        scope.where(user_id: user.id)
      end
    end
  end

  def index?
    # Anyone can view a list of orders they're allowed to see
    true
  end

  def show?
    # Admins can see any order
    # Staff can see orders they created or any non-staff order
    # Customers can only see their own orders
    admin_or_above? || 
    record.user_id == user.id || 
    (staff? && (record.created_by_staff_id == user.staff_member&.id || !record.staff_created))
  end

  def update?
    # Admins can update any order
    # Staff can update orders they created
    # Customers cannot update orders
    admin_or_above? || 
    (staff? && record.created_by_staff_id == user.staff_member&.id)
  end

  def destroy?
    # Only admins can destroy orders
    admin_or_above?
  end

  def acknowledge?
    # Admins can acknowledge any order
    # Staff can acknowledge any non-staff order or orders they created
    admin_or_above? || 
    (staff? && (record.created_by_staff_id == user.staff_member&.id || !record.staff_created))
  end

  def unacknowledge?
    # Same permissions as acknowledge
    acknowledge?
  end
end
```

#### User Policy

The User policy controls who can view, create, update, and manage users:

```ruby
# app/policies/user_policy.rb
class UserPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.super_admin?
        # Super admins can see all users
        scope.all
      elsif user.admin?
        # Admins can see all users except super admins
        scope.where.not(role: 'super_admin')
      elsif user.staff?
        # Staff can only see themselves and customers
        scope.where(id: user.id).or(scope.where(role: 'customer'))
      else
        # Regular customers can only see themselves
        scope.where(id: user.id)
      end
    end
  end

  def index?
    # Only admins and above can list users
    admin_or_above?
  end

  def show?
    # Admins can see any user (except super_admins for regular admins)
    # Staff and customers can only see themselves
    super_admin? || 
    (admin? && record.role != 'super_admin') || 
    record.id == user.id
  end

  def create?
    # Only admins and above can create users
    admin_or_above?
  end

  def update?
    # Super admins can update any user
    # Admins can update any user except super admins
    # Staff and customers can only update themselves
    super_admin? || 
    (admin? && record.role != 'super_admin') || 
    record.id == user.id
  end

  def destroy?
    # Super admins can delete any user except themselves
    # Admins can delete staff and customers
    # Staff and customers cannot delete users
    (super_admin? && record.id != user.id) || 
    (admin? && record.role.in?(['staff', 'customer']))
  end

  # For role assignment
  def assign_role?
    # Super admins can assign any role except super_admin
    # Admins can assign staff and customer roles
    # Staff and customers cannot assign roles
    super_admin? || 
    (admin? && record.role.in?(['staff', 'customer']))
  end
end
```

#### Menu Item Policy

The Menu Item policy controls who can view, create, update, and manage menu items:

```ruby
# app/policies/menu_item_policy.rb
class MenuItemPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      # Everyone can see all menu items
      # The visibility of menu items is controlled at the menu item level (active/inactive)
      scope.all
    end
  end

  def index?
    # Anyone can view the list of menu items
    true
  end

  def show?
    # Anyone can view menu item details
    true
  end

  def create?
    # Only admins and above can create menu items
    admin_or_above?
  end

  def update?
    # Only admins and above can update menu items
    admin_or_above?
  end

  def destroy?
    # Only admins and above can delete menu items
    admin_or_above?
  end

  def update_inventory?
    # Admins can update inventory for any item
    # Staff can update inventory if they have permission
    admin_or_above? || staff?
  end

  def toggle_active?
    # Only admins and above can activate/deactivate menu items
    admin_or_above?
  end
end
```

## Using Policies in Controllers

Policies are used in controllers to authorize actions and scope queries:

```ruby
# Example controller using Pundit
class OrdersController < ApplicationController
  before_action :set_order, only: [:show, :update, :destroy, :acknowledge, :unacknowledge]
  
  # GET /orders
  def index
    # policy_scope automatically filters orders based on the user's role
    @orders = policy_scope(Order)
    
    # Additional filtering can be applied after policy_scope
    if params[:status].present?
      @orders = @orders.where(status: params[:status])
    end
    
    render json: @orders
  end
  
  # GET /orders/:id
  def show
    # authorize checks if the user can perform the show action on this order
    authorize @order
    render json: @order
  end
  
  # POST /orders
  def create
    @order = Order.new(order_params)
    @order.user = current_user
    
    # For staff-created orders, record the staff member
    if current_user.staff? && current_user.staff_member.present?
      @order.created_by_staff_id = current_user.staff_member.id
      @order.staff_created = true
    end
    
    # authorize checks if the user can create orders
    authorize @order
    
    if @order.save
      render json: @order, status: :created
    else
      render json: { errors: @order.errors }, status: :unprocessable_entity
    end
  end
  
  # PATCH /orders/:id
  def update
    # authorize checks if the user can update this order
    authorize @order
    
    if @order.update(order_params)
      render json: @order
    else
      render json: { errors: @order.errors }, status: :unprocessable_entity
    end
  end
  
  # DELETE /orders/:id
  def destroy
    # authorize checks if the user can delete this order
    authorize @order
    @order.destroy
    head :no_content
  end
  
  # POST /orders/:id/acknowledge
  def acknowledge
    # authorize checks if the user can acknowledge this order
    authorize @order, :acknowledge?
    
    # Acknowledge logic...
  end
  
  private
  
  def set_order
    @order = Order.find(params[:id])
  end
  
  def order_params
    params.require(:order).permit(:status, :total, :items_attributes)
  end
end
```

## Best Practices

1. **Always Use Policy Scopes**: Use `policy_scope` for index actions to ensure users only see records they're allowed to access
2. **Authorize Individual Records**: Use `authorize @record` for show, update, and destroy actions
3. **Custom Policy Methods**: Define custom policy methods for non-CRUD actions (e.g., `acknowledge?`)
4. **Keep Policies Simple**: Each policy method should focus on a single authorization concern
5. **Test Your Policies**: Write comprehensive tests for your policy classes to ensure they work as expected

## Adding New Policies

To add a new policy for a resource:

1. Create a new policy class in `app/policies/` that inherits from ApplicationPolicy
2. Define the Scope class with a resolve method to filter queryable records
3. Implement the necessary policy methods (index?, show?, create?, update?, destroy?)
4. Add any custom policy methods for non-CRUD actions
5. Use the policy in your controller with `authorize` and `policy_scope`

## Conclusion

Pundit provides a powerful and flexible authorization system that allows Shimizu Order Suite to implement fine-grained access control based on user roles and resource ownership. By centralizing authorization logic in policy classes, the application maintains a clean separation of concerns and makes it easier to reason about and update permission rules.
