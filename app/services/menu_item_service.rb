# app/services/menu_item_service.rb
class MenuItemService < TenantScopedService
  attr_accessor :current_user

  # List menu items with optional filtering
  def list_items(params = {})
    # Log the request parameters for debugging
    Rails.logger.debug "[MenuItemService#list_items] Params: #{params.inspect}"
    
    # Base query with tenant isolation
    if is_admin? && (params[:admin].present? || params[:show_all].present? || params[:view_type] == 'admin')
      base_scope = scope_query(MenuItem).all
    else
      # For non-admin users, only show items that are currently available and not hidden
      base_scope = scope_query(MenuItem).currently_available.where(hidden: false)
    end

    # Filter by specific menu_id if provided in params
    if params[:menu_id].present?
      base_scope = base_scope.where(menu_id: params[:menu_id])
    # Filter by the restaurant's current menu if available and admin is not requesting all items
    elsif restaurant&.current_menu_id.present? && !(is_admin? && params[:admin].present?)
      base_scope = base_scope.where(menu_id: restaurant.current_menu_id)
    end

    # Apply additional filters based on params
    
    # Filter by featured status if requested
    if params[:featured].present? && params[:featured].to_s.downcase == 'true'
      base_scope = base_scope.where(featured: true)
    end
    
    # Filter by seasonal status if requested
    if params[:seasonal].present? && params[:seasonal].to_s.downcase == 'true'
      base_scope = base_scope.where(seasonal: true)
    end
    
    # Explicit hidden filter for admin users
    if is_admin? && params[:hidden].present?
      hidden_value = params[:hidden].to_s.downcase == 'true'
      base_scope = base_scope.where(hidden: hidden_value)
    end
    
    # Category filter if present => now uses many-to-many
    if params[:category_id].present?
      base_scope = base_scope.joins(:categories).where(categories: { id: params[:category_id] })
    end
    
    # Search filter if present
    if params[:search_query].present?
      search_term = "%#{params[:search_query].downcase}%"
      
      # Check if search term matches any category name
      matching_category_ids = scope_query(Category).where("LOWER(name) LIKE ?", search_term).pluck(:id)
      
      if matching_category_ids.present?
        Rails.logger.debug "[MenuItemService#list_items] Found matching categories: #{matching_category_ids}"
        # If we found matching categories, include items from those categories
        base_scope = base_scope.left_joins(:categories)
                              .where("LOWER(menu_items.name) LIKE ? OR LOWER(menu_items.description) LIKE ? OR categories.id IN (?)", 
                                     search_term, search_term, matching_category_ids)
                              .distinct
      else
        # Standard search in name and description
        base_scope = base_scope.where("LOWER(menu_items.name) LIKE ? OR LOWER(menu_items.description) LIKE ?", search_term, search_term)
      end
      
      Rails.logger.debug "[MenuItemService#list_items] Applying search filter with term: #{params[:search_query]}"
    end
    
    # Sort by name
    base_scope = base_scope.order(:name)

    # Optimize response based on view_type
    # 'list' = minimal data for listings
    # 'admin' = full data for admin views
    # 'detail' = full data including options
    includes_scope = case params[:view_type]
                    when 'list'
                      base_scope
                    else
                      base_scope.includes(option_groups: :options)
                    end
    
    Rails.logger.debug "[MenuItemService#list_items] Returning #{includes_scope.count} items"
    includes_scope
  end

  # Find a specific menu item by ID
  def find_item(id)
    item = scope_query(MenuItem).includes(option_groups: :options).find(id)
    
    # For non-admin users, check if the item is hidden
    if !is_admin? && item.hidden
      raise ActiveRecord::RecordNotFound, "Item not found"
    end
    
    item
  rescue ActiveRecord::RecordNotFound
    raise ActiveRecord::RecordNotFound, "Item not found"
  end

  # Create a new menu item
  def create_item(menu_item_params, category_ids = nil, available_days = nil)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?

    # Ensure the menu belongs to the current restaurant
    menu = scope_query(Menu).find_by(id: menu_item_params[:menu_id])
    return { success: false, errors: ["Menu not found"], status: :not_found } unless menu

    menu_item = MenuItem.new(menu_item_params.except(:image))

    # Assign categories before saving if category_ids param is given
    if category_ids.present?
      menu_item.category_ids = Array(category_ids)
    end
    
    # Handle available_days as an array
    if available_days.present?
      menu_item.available_days = Array(available_days).map(&:to_i)
    end

    if menu_item.save
      # Handle image upload if present
      file = menu_item_params[:image]
      if file.present? && file.respond_to?(:original_filename)
        begin
          ext = File.extname(file.original_filename)
          new_filename = "menu_item_#{menu_item.id}_#{Time.now.to_i}#{ext}"
          public_url = S3Uploader.upload(file, new_filename)
          menu_item.update!(image_url: public_url)
        rescue => e
          Rails.logger.error "[MenuItemService] Image upload failed for menu_item #{menu_item.id}: #{e.message}"
          Rails.logger.error "[MenuItemService] Backtrace: #{e.backtrace.join("\n")}"
          # Don't fail the entire operation, just log the error
          # The menu item was already created successfully
        end
      end

      { success: true, menu_item: menu_item, status: :created }
    else
      { success: false, errors: menu_item.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Update an existing menu item
  def update_item(id, menu_item_params, category_ids = nil, available_days = nil)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?

    menu_item = scope_query(MenuItem).find(id)
    
    # Assign categories before updating if category_ids param is given
    if category_ids.present?
      menu_item.category_ids = Array(category_ids)
    end
    
    # Handle available_days as an array
    if available_days.present?
      if available_days.blank? || available_days == []
        # Clear available days if empty array or blank is provided
        menu_item.available_days = []
      else
        menu_item.available_days = Array(available_days).map(&:to_i)
      end
    elsif menu_item_params.keys.include?("name") && 
          menu_item_params.keys.include?("description") && 
          menu_item_params.keys.include?("price")
      # If we're in the menu edit form and available_days is not present,
      # it means all days were deselected
      menu_item.available_days = []
    end
    
    if menu_item.update(menu_item_params.except(:image))
      # Handle image if present
      file = menu_item_params[:image]
      if file.present? && file.respond_to?(:original_filename)
        begin
          ext = File.extname(file.original_filename)
          new_filename = "menu_item_#{menu_item.id}_#{Time.now.to_i}#{ext}"
          public_url = S3Uploader.upload(file, new_filename)
          menu_item.update!(image_url: public_url)
        rescue => e
          Rails.logger.error "[MenuItemService] Image upload failed for menu_item #{menu_item.id}: #{e.message}"
          Rails.logger.error "[MenuItemService] Backtrace: #{e.backtrace.join("\n")}"
          # Don't fail the entire operation, just log the error
          # The menu item was already updated successfully
        end
      end

      { success: true, menu_item: menu_item }
    else
      { success: false, errors: menu_item.errors.full_messages, status: :unprocessable_entity }
    end
  rescue ActiveRecord::RecordNotFound
    { success: false, errors: ["Menu item not found"], status: :not_found }
  end

  # Delete a menu item
  def delete_item(id)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?

    menu_item = scope_query(MenuItem).find(id)
    menu_item.destroy
    
    { success: true }
  rescue ActiveRecord::RecordNotFound
    { success: false, errors: ["Menu item not found"], status: :not_found }
  end

  # Upload an image for a menu item
  def upload_image(id, image_file)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?

    menu_item = scope_query(MenuItem).find(id)
    
    unless image_file
      return { success: false, errors: ["No image file uploaded"], status: :unprocessable_entity }
    end

    begin
      ext = File.extname(image_file.original_filename)
      new_filename = "menu_item_#{menu_item.id}_#{Time.now.to_i}#{ext}"
      public_url = S3Uploader.upload(image_file, new_filename)
      menu_item.update!(image_url: public_url)

      { success: true, menu_item: menu_item }
    rescue => e
      Rails.logger.error "[MenuItemService] Standalone image upload failed for menu_item #{id}: #{e.message}"
      Rails.logger.error "[MenuItemService] Backtrace: #{e.backtrace.join("\n")}"
      { success: false, errors: ["Image upload failed: #{e.message}"], status: :unprocessable_entity }
    end
  rescue ActiveRecord::RecordNotFound
    { success: false, errors: ["Menu item not found"], status: :not_found }
  end

  # Mark a menu item as damaged
  def mark_as_damaged(id, params)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless current_user&.staff_or_above?

    menu_item = scope_query(MenuItem).find(id)

    unless menu_item.enable_stock_tracking
      return { success: false, errors: ["Inventory tracking is not enabled for this item"], status: :unprocessable_entity }
    end

    quantity = params[:quantity].to_i
    reason = params[:reason].presence || "No reason provided"
    from_order = params[:order_id].present?

    if quantity <= 0
      return { success: false, errors: ["Quantity must be greater than zero"], status: :unprocessable_entity }
    end

    # If this is coming from an order edit (through InventoryReversionDialog),
    # we need special handling to avoid duplicate inventory adjustments
    if from_order
      # Just increment the damaged count - the inventory adjustment will be handled by orders_controller
      if menu_item.increment_damaged_only(quantity, reason, current_user)
        { success: true, menu_item: menu_item }
      else
        { success: false, errors: ["Failed to mark items as damaged"], status: :unprocessable_entity }
      end
    else
      # Regular damaged marking (not from order edit)
      if menu_item.mark_as_damaged(quantity, reason, current_user)
        { success: true, menu_item: menu_item }
      else
        { success: false, errors: ["Failed to mark items as damaged"], status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotFound
    { success: false, errors: ["Menu item not found"], status: :not_found }
  end

  # Update stock quantity for a menu item
  def update_stock(id, params)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless current_user&.staff_or_above?

    menu_item = scope_query(MenuItem).find(id)

    unless menu_item.enable_stock_tracking
      return { success: false, errors: ["Inventory tracking is not enabled for this item"], status: :unprocessable_entity }
    end

    new_quantity = params[:stock_quantity].to_i
    reason_type = params[:reason_type] || "adjustment"
    reason_details = params[:reason_details].presence

    if new_quantity < 0
      return { success: false, errors: ["Stock quantity cannot be negative"], status: :unprocessable_entity }
    end

    if menu_item.update_stock_quantity(new_quantity, reason_type, reason_details, current_user)
      { success: true, menu_item: menu_item }
    else
      { success: false, errors: ["Failed to update stock quantity"], status: :unprocessable_entity }
    end
  rescue ActiveRecord::RecordNotFound
    { success: false, errors: ["Menu item not found"], status: :not_found }
  end

  # Get stock audits for a menu item
  def get_stock_audits(id)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?

    menu_item = scope_query(MenuItem).find(id)

    unless menu_item.enable_stock_tracking
      return { success: false, errors: ["Inventory tracking is not enabled for this item"], status: :unprocessable_entity }
    end

    audits = menu_item.menu_item_stock_audits.order(created_at: :desc).limit(50)
    
    { success: true, audits: audits }
  rescue ActiveRecord::RecordNotFound
    { success: false, errors: ["Menu item not found"], status: :not_found }
  end

  # Copy a menu item to another menu or within the same menu
  def copy_item(id, params)
    return { success: false, errors: ["Forbidden"], status: :forbidden } unless is_admin?
    
    source_item = scope_query(MenuItem).find(id)
    target_menu_id = params[:target_menu_id]
    category_ids = params[:category_ids] || []
    new_name = params[:new_name]
    
    unless target_menu_id.present?
      return { success: false, errors: ["Target menu ID is required"], status: :unprocessable_entity }
    end
    
    # Ensure the target menu belongs to the current restaurant
    target_menu = scope_query(Menu).find_by(id: target_menu_id)
    return { success: false, errors: ["Target menu not found"], status: :not_found } unless target_menu
    
    # Create a new item with the same attributes but new menu_id
    new_item = source_item.dup
    new_item.menu_id = target_menu_id
    
    # Set a custom name if provided, otherwise append "(Copy)" for same-menu cloning
    if new_name.present?
      new_item.name = new_name
    elsif target_menu_id.to_s == source_item.menu_id.to_s
      new_item.name = "#{source_item.name} (Copy)"
    end
    
    # Assign categories
    new_item.category_ids = category_ids if category_ids.present?
    
    # Reset inventory audit history while keeping current inventory values
    if new_item.enable_stock_tracking
      new_item.stock_quantity = source_item.stock_quantity
      new_item.damaged_quantity = source_item.damaged_quantity
      new_item.low_stock_threshold = source_item.low_stock_threshold
      # Don't copy inventory_audits - they should start fresh
    end
    
    # Keep the same image URL
    new_item.image_url = source_item.image_url
    
    # Tenant isolation is already handled by the scope_query method
    # and the tenant context set in the controller
    
    # Save the new item
    if new_item.save
      # Copy all option groups and their options
      if source_item.option_groups.present?
        source_item.option_groups.each do |source_group|
          # Create a new option group for the new item
          new_group = source_group.dup
          new_group.menu_item_id = new_item.id
          
          if new_group.save
            # Copy all options within the group
            source_group.options.each do |source_option|
              new_option = source_option.dup
              new_option.option_group_id = new_group.id
              new_option.save
            end
          end
        end
      end
      
      { success: true, menu_item: new_item, status: :created }
    else
      { success: false, errors: new_item.errors.full_messages, status: :unprocessable_entity }
    end
  rescue ActiveRecord::RecordNotFound
    { success: false, errors: ["Menu item not found"], status: :not_found }
  end

  private

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
