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
        
        # Enhanced debug info
        Rails.logger.info("Staff member ID: #{staff_id}")
        Rails.logger.info("Orders created by this staff: #{scope.where(created_by_staff_id: staff_id).count}")
        Rails.logger.info("Customer orders: #{scope.where(staff_created: false, is_staff_order: false).count}")
        Rails.logger.info("Total orders in scope before filtering: #{scope.count}")
        
        # Updated policy: Staff can see orders they created OR customer orders
        # Customer orders are identified by staff_created: false AND is_staff_order: false
        filtered_orders = scope.where(
          "(created_by_staff_id = :staff_id) OR (staff_created = :is_customer_created AND is_staff_order = :is_customer_order)", 
          staff_id: staff_id, 
          is_customer_created: false,
          is_customer_order: false
        )
        
        # Log the final count and SQL for debugging
        Rails.logger.info("Total orders after filtering: #{filtered_orders.count}")
        Rails.logger.info("SQL query: #{filtered_orders.to_sql}")
        Rails.logger.info("Staff ID used in query: #{staff_id}")
        
        # Return the filtered orders
        filtered_orders
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
    # Staff can see orders they created or online orders
    # Customers can only see their own orders
    admin_or_above? || 
    record.user_id == user.id || 
    (staff? && (record.created_by_staff_id == user.staff_member&.id || record.source == 'online'))
  end

  def acknowledge?
    # Only admin or above can acknowledge orders
    admin_or_above?
  end

  def create?
    # Anyone can create an order
    true
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
    # Staff can acknowledge online orders or orders they created
    admin_or_above? || 
    (staff? && (record.created_by_staff_id == user.staff_member&.id || record.source == 'online'))
  end

  def unacknowledge?
    # Same permissions as acknowledge
    acknowledge?
  end
end
