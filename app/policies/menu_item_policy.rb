# app/policies/menu_item_policy.rb
class MenuItemPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      # Everyone can see all menu items
      # The visibility of menu items is controlled at the menu item level (active/inactive)
      scope.all
    end
  end

  def index?
    # Anyone can view the list of menu items
    true
  end

  def show?
    # Anyone can view menu item details
    true
  end

  def create?
    # Only admins and above can create menu items
    admin_or_above?
  end

  def update?
    # Only admins and above can update menu items
    admin_or_above?
  end

  def destroy?
    # Only admins and above can delete menu items
    admin_or_above?
  end

  def update_inventory?
    # Admins can update inventory for any item
    # Staff can update inventory if they have permission
    admin_or_above? || staff?
  end

  def toggle_active?
    # Only admins and above can activate/deactivate menu items
    admin_or_above?
  end
end
