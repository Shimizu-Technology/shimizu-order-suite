class OrderPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.admin?
        # Admins can see all orders
        scope.all
      elsif user.staff?
        # Staff can only see orders they created
        scope.where(created_by_id: user.id)
      else
        # Regular users can only see their own orders
        scope.where(user_id: user.id)
      end
    end
  end

  def show?
    user.admin? || record.created_by_id == user.id || record.user_id == user.id
  end

  def create?
    true # Anyone can create an order
  end

  def update?
    user.admin? || record.created_by_id == user.id
  end

  def destroy?
    user.admin? || record.created_by_id == user.id
  end
end