# app/policies/order_policy.rb
class OrderPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.nil?
        # Unauthenticated users can't see any orders
        scope.none
      elsif user.admin_or_above?
        # Admins and super admins can see all orders
        scope.all
      elsif user.staff?
        # Staff can see:
        # 1. Orders they created (via user_id or staff_id)
        # 2. Online customer orders (not created by staff)
        staff_id = user.staff_member&.id
        user_id = user.id
        
        # Return orders created by this staff, this user, or online orders
        scope.where(
          "(created_by_user_id = :user_id) OR (created_by_staff_id = :staff_id) OR (staff_created = FALSE)",
          user_id: user_id,
          staff_id: staff_id
        )
      else
        # Regular customers can only see their own orders
        scope.where(user_id: user.id)
      end
    end
  end

  # Anyone authenticated can view orders they're allowed to see
  def index?
    !user.nil?
  end

  # Show allowed based on user role and ownership
  def show?
    return false if user.nil?
    admin_or_above? || 
      record.user_id == user.id || 
      staff_can_access_order?
  end

  # Anyone authenticated can create an order
  def create?
    !user.nil?
  end

  # Update allowed based on user role and ownership
  def update?
    return false if user.nil?
    admin_or_above? || staff_can_modify_order?
  end

  # Only admins can destroy orders
  def destroy?
    admin_or_above?
  end

  # Acknowledge permission
  def acknowledge?
    return false if user.nil?
    admin_or_above? || staff_can_access_order?
  end

  # Same permissions as acknowledge
  def unacknowledge?
    acknowledge?
  end

  private

  # Helper method for staff access to orders
  def staff_can_access_order?
    return false unless staff?
    
    # Staff can access orders they created or online orders
    record.created_by_user_id == user.id || 
      record.created_by_staff_id == user.staff_member&.id || 
      !record.staff_created
  end

  # Helper method for staff modification of orders
  def staff_can_modify_order?
    return false unless staff?
    
    # Staff can only modify orders they created
    record.created_by_user_id == user.id || 
      record.created_by_staff_id == user.staff_member&.id
  end
end
