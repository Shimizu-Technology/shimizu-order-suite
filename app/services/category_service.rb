# app/services/category_service.rb
class CategoryService < TenantScopedService
  attr_accessor :current_user

  # List all categories for a menu
  def list_categories(menu_id)
    menu = menu_id ? scope_query(Menu).find_by(id: menu_id) : nil
    categories = menu ? menu.categories.order(:position, :name) : scope_query(Category).order(:position, :name)
    categories
  end

  # Create a new category for a menu
  def create_category(menu_id, category_params)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    
    menu = scope_query(Menu).find_by(id: menu_id)
    return { success: false, errors: ["Menu not found"], status: :not_found } unless menu
    
    category = menu.categories.build(category_params)
    
    if category.save
      { success: true, category: category, status: :created }
    else
      { success: false, errors: category.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Update an existing category
  def update_category(menu_id, category_id, category_params)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    
    menu = scope_query(Menu).find_by(id: menu_id)
    return { success: false, errors: ["Menu not found"], status: :not_found } unless menu
    
    category = menu.categories.find_by(id: category_id)
    return { success: false, errors: ["Category not found"], status: :not_found } unless category
    
    if category.update(category_params)
      { success: true, category: category }
    else
      { success: false, errors: category.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Delete a category
  def delete_category(menu_id, category_id)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    
    menu = scope_query(Menu).find_by(id: menu_id)
    return { success: false, errors: ["Menu not found"], status: :not_found } unless menu
    
    category = menu.categories.find_by(id: category_id)
    return { success: false, errors: ["Category not found"], status: :not_found } unless category
    
    if category.menu_items.empty?
      category.destroy
      { success: true }
    else
      { success: false, errors: ["Cannot delete category with associated menu items"], status: :unprocessable_entity }
    end
  end

  private

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
