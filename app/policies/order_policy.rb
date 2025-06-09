# app/policies/order_policy.rb
class OrderPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      case user.role
      when 'admin', 'super_admin'
        # Admins and super admins can see all orders
        scope.all
      when 'staff'
        # Staff can only see orders they created as employees (via StaffOrderModal)
        scope.where(created_by_user_id: user.id, staff_created: true)
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
    # Staff can only see orders they created as employees (staff_created: true)
    # Customers can only see their own orders
    user.role.in?(['admin', 'super_admin']) || 
    record.user_id == user.id || 
    (user.role == 'staff' && record.created_by_user_id == user.id && record.staff_created?)
  end

  def acknowledge?
    # Only admin or above can acknowledge orders
    user.role.in?(['admin', 'super_admin'])
  end

  def create?
    # Anyone can create an order
    true
  end

  def update?
    # Admins can update any order
    # Staff can update orders they created as employees (staff_created: true)
    # Customers cannot update orders
    user.role.in?(['admin', 'super_admin']) || 
    (user.role == 'staff' && record.created_by_user_id == user.id && record.staff_created?)
  end

  def destroy?
    # Only admins can destroy orders
    user.role.in?(['admin', 'super_admin'])
  end

  def unacknowledge?
    # Same permissions as acknowledge
    acknowledge?
  end
end
