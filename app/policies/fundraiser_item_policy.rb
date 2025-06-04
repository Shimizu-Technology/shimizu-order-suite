# app/policies/fundraiser_item_policy.rb

class FundraiserItemPolicy < ApplicationPolicy
  def index?
    # Public access for active fundraisers
    return true if record.fundraiser.active?
    # Allow admin users of the same restaurant
    user.present? && user.admin? && record.fundraiser.restaurant_id == user.restaurant_id
  end

  def show?
    # Allow admin users of the same restaurant or any user if the fundraiser is active
    return true if record.fundraiser.active? # Public access for active fundraisers
    user.present? && user.admin? && record.fundraiser.restaurant_id == user.restaurant_id
  end

  def create?
    # Only admin users of the same restaurant can create
    user.present? && user.admin? && record.fundraiser.restaurant_id == user.restaurant_id
  end

  def update?
    # Only admin users of the same restaurant can update
    user.present? && user.admin? && record.fundraiser.restaurant_id == user.restaurant_id
  end

  def destroy?
    # Only admin users of the same restaurant can destroy
    user.present? && user.admin? && record.fundraiser.restaurant_id == user.restaurant_id
  end

  class Scope < Scope
    def resolve
      # For nil users (public access), only return items from active fundraisers
      if user.nil?
        scope.joins(:fundraiser).where(fundraisers: { active: true })
      # For admin users, return all fundraiser items for their restaurant
      elsif user.admin?
        scope.joins(:fundraiser).where(fundraisers: { restaurant_id: user.restaurant_id })
      else
        # For regular users, only return items from active fundraisers
        scope.joins(:fundraiser).where(fundraisers: { active: true })
      end
    end
  end
end
