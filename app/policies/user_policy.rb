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

  # For resending invites
  def resend_invite?
    # Same permissions as update
    update?
  end

  # For admin password reset
  def admin_reset_password?
    # Same permissions as update
    update?
  end
end
