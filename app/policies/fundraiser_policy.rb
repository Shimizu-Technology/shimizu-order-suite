# app/policies/fundraiser_policy.rb
class FundraiserPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.nil?
        # Public users can only see active fundraisers
        scope.active
      elsif user.admin_or_above?
        # Admins and super admins can see all fundraisers for their restaurant
        scope.all
      elsif user.staff?
        # Staff can see all fundraisers for their restaurant
        scope.all
      else
        # Regular customers can only see active fundraisers
        scope.active
      end
    end
  end

  def index?
    # Anyone can view a list of fundraisers they're allowed to see
    true
  end

  def show?
    # Anyone can view an active fundraiser
    # Admins and staff can view any fundraiser for their restaurant
    record.active? || (user.present? && user.staff_or_above?)
  end

  def by_slug?
    # Use same permissions as show? since this is just another way to view a fundraiser
    show?
  end

  def create?
    # Only admins or above can create fundraisers
    user.admin_or_above?
  end

  def update?
    # Only admins or above can update fundraisers
    user.admin_or_above?
  end

  def destroy?
    # Only admins or above can destroy fundraisers
    user.admin_or_above?
  end
end
