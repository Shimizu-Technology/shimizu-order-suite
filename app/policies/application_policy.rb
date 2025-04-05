# frozen_string_literal: true

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

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
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
