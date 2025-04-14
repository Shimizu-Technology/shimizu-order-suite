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
      # Get all categories for this menu with position greater than the deleted category
      categories_to_update = menu.categories.where('position > ?', category.position)
      
      # Delete the category
      category.destroy
      
      # Rebalance positions for remaining categories
      categories_to_update.each do |cat|
        cat.update(position: cat.position - 1)
      end
      
      { success: true }
    else
      { success: false, errors: ["Cannot delete category with associated menu items"], status: :unprocessable_entity }
    end
  end
  
  # Batch update positions for multiple categories
  def batch_update_positions(menu_id, positions_data)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    
    menu = scope_query(Menu).find_by(id: menu_id)
    return { success: false, errors: ["Menu not found"], status: :not_found } unless menu
    
    # Validate that all category IDs exist in this menu
    category_ids = positions_data.map { |data| data[:id] }
    categories = menu.categories.where(id: category_ids)
    
    if categories.count != category_ids.uniq.count
      return { success: false, errors: ["One or more categories not found"], status: :not_found }
    end
    
    # Update positions in a transaction
    updated_categories = []
    
    ActiveRecord::Base.transaction do
      positions_data.each do |position_data|
        category = categories.find { |cat| cat.id.to_s == position_data[:id].to_s }
        category.update!(position: position_data[:position])
        updated_categories << category
      end
      
      # Normalize positions to ensure they are sequential
      normalize_positions(menu)
    end
    
    { success: true, categories: menu.categories.order(:position) }
  rescue => e
    { success: false, errors: [e.message], status: :unprocessable_entity }
  end

  private

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
  
  # Normalize positions to ensure they are sequential (1, 2, 3...)
  def normalize_positions(menu)
    # Get all categories for this menu ordered by position
    categories = menu.categories.order(:position)
    
    # Update positions to be sequential
    categories.each_with_index do |category, index|
      category.update_column(:position, index + 1) if category.position != index + 1
    end
  end
end
