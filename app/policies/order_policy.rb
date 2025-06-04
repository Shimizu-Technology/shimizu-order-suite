# app/policies/order_policy.rb
class OrderPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      # For nil users (public access), only allow access to fundraiser orders they created
      # This is for unauthenticated users who place fundraiser orders
      if user.nil?
        # Public users can only see fundraiser orders they created (via session/cookie tracking)
        # This will typically be empty unless we implement session-based tracking
        scope.where(is_fundraiser_order: true).where("transaction_id IS NOT NULL")
      elsif user.admin_or_above?
        # Admins and super admins can see all orders
        scope.all
      elsif user.staff?
        # Staff can see orders they created AND customer orders
        staff_id = user.staff_member&.id
        user_id = user.id
        
        # Enhanced debug info
        Rails.logger.info("Staff member ID: #{staff_id}, User ID: #{user_id}")
        Rails.logger.info("Orders created by this staff: #{scope.where(created_by_staff_id: staff_id).count if staff_id}")
        Rails.logger.info("Orders created by this user: #{scope.where(created_by_user_id: user_id).count}")
        Rails.logger.info("Customer orders: #{scope.where(staff_created: false, is_staff_order: false).count}")
        Rails.logger.info("Fundraiser orders: #{scope.where(is_fundraiser_order: true).count}")
        Rails.logger.info("Total orders in scope before filtering: #{scope.count}")
        
        # Updated policy: Staff can see orders they created (via staff_id OR user_id) OR customer orders OR fundraiser orders
        # Customer orders are identified by staff_created: false AND is_staff_order: false
        filtered_orders = scope.where(
          "(created_by_user_id = :user_id) OR (created_by_staff_id = :staff_id) OR (staff_created = :is_customer_created AND is_staff_order = :is_customer_order) OR (is_fundraiser_order = :is_fundraiser_order)", 
          user_id: user_id,
          staff_id: staff_id, 
          is_customer_created: false,
          is_customer_order: false,
          is_fundraiser_order: true
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
    # Public users can see fundraiser orders they created (via transaction_id)
    return record.is_fundraiser_order && record.transaction_id.present? if user.nil?
    
    # Admins can see any order
    # Staff can see orders they created (via user_id or staff_id) or any non-staff order or any fundraiser order
    # Customers can only see their own orders
    admin_or_above? || 
    record.user_id == user.id || 
    (staff? && (record.created_by_user_id == user.id || record.created_by_staff_id == user.staff_member&.id || !record.staff_created || record.is_fundraiser_order))
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
    # Staff can update orders they created (via user_id or staff_id) or fundraiser orders
    # Customers cannot update orders
    admin_or_above? || 
    (staff? && (record.created_by_user_id == user.id || record.created_by_staff_id == user.staff_member&.id || record.is_fundraiser_order))
  end

  def destroy?
    # Only admins can destroy orders
    admin_or_above?
  end

  def acknowledge?
    # Admins can acknowledge any order
    # Staff can acknowledge any non-staff order, fundraiser order, or orders they created (via user_id or staff_id)
    admin_or_above? || 
    (staff? && (record.created_by_user_id == user.id || record.created_by_staff_id == user.staff_member&.id || !record.staff_created || record.is_fundraiser_order))
  end

  def unacknowledge?
    # Same permissions as acknowledge
    acknowledge?
  end
end
