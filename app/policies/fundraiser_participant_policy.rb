# app/policies/fundraiser_participant_policy.rb
class FundraiserParticipantPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.nil?
        # Public users can only see active participants
        scope.active
      elsif user.admin_or_above?
        # Admins and super admins can see all participants
        scope.all
      elsif user.staff?
        # Staff can see all participants
        scope.all
      else
        # Regular customers can only see active participants
        scope.active
      end
    end
  end

  def index?
    # Anyone can view a list of participants they're allowed to see
    true
  end

  def show?
    # Anyone can view an active participant
    # Admins and staff can view any participant
    record.active? || (user.present? && user.staff_or_above?)
  end

  def create?
    # Only admins or above can create participants
    user.admin_or_above?
  end

  def update?
    # Only admins or above can update participants
    user.admin_or_above?
  end

  def destroy?
    # Only admins or above can delete participants
    user.admin_or_above?
  end

  def bulk_import?
    # Only admins or above can bulk import participants
    user.admin_or_above?
  end
end
