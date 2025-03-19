class MenuItemsController < ApplicationController
  # 1) For index & show, optional_authorize => public can see
  before_action :optional_authorize, only: [ :index, :show ]

  # 2) For other actions, require token + admin
  before_action :authorize_request, except: [ :index, :show ]

  # Mark all actions as public endpoints that don't require restaurant context
  def public_endpoint?
    true
  end

  # GET /menu_items
  def index
    # Get the restaurant from the params
    restaurant_id = params[:restaurant_id]
    restaurant = Restaurant.find_by(id: restaurant_id) if restaurant_id.present?

    # If admin AND params[:admin] or params[:show_all] => show all. Otherwise only unexpired.
    if is_admin? && (params[:admin].present? || params[:show_all].present?)
      base_scope = MenuItem.all
    else
      base_scope = MenuItem.currently_available
    end

    # Filter by specific menu_id if provided in params
    if params[:menu_id].present?
      base_scope = base_scope.where(menu_id: params[:menu_id])
    # Filter by the restaurant's current menu if available and admin is not requesting all items
    elsif restaurant&.current_menu_id.present? && !(is_admin? && params[:admin].present?)
      base_scope = base_scope.where(menu_id: restaurant.current_menu_id)
    end

    # Sort by name
    base_scope = base_scope.order(:name)

    # Category filter if present => now uses many-to-many:
    # e.g. ?category_id=3
    if params[:category_id].present?
      base_scope = base_scope.joins(:categories).where(categories: { id: params[:category_id] })
    end

    items = base_scope.includes(option_groups: :options)

    render json: items.as_json(
      include: {
        option_groups: {
          include: {
            options: {
              only: [ :id, :name, :available, :is_preselected ],
              methods: [ :additional_price_float ]
            }
          }
        }
      }
    )
  end

  # GET /menu_items/:id
  def show
    item = MenuItem.includes(option_groups: :options).find(params[:id])
    render json: item.as_json(
      include: {
        option_groups: {
          include: {
            options: {
              only: [ :id, :name, :available, :is_preselected ],
              methods: [ :additional_price_float ]
            }
          }
        }
      }
    )
  end

  # POST /menu_items
  def create
    Rails.logger.info "=== MenuItemsController#create ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    @menu_item = MenuItem.new(menu_item_params.except(:image))

    # Assign categories before saving if category_ids param is given
    if params[:menu_item][:category_ids].present?
      @menu_item.category_ids = Array(params[:menu_item][:category_ids])
    end
    
    # Handle available_days as an array
    if params[:menu_item][:available_days].present?
      Rails.logger.info "Available days param: #{params[:menu_item][:available_days].inspect}"
      Rails.logger.info "Available days param class: #{params[:menu_item][:available_days].class}"
      
      available_days = Array(params[:menu_item][:available_days]).map(&:to_i)
      Rails.logger.info "Processed available days: #{available_days.inspect}"
      
      @menu_item.available_days = available_days
    end

    if @menu_item.save
      Rails.logger.info "Created MenuItem => #{@menu_item.inspect}"

      # Handle image upload if present
      file = menu_item_params[:image]
      if file.present? && file.respond_to?(:original_filename)
        ext = File.extname(file.original_filename)
        new_filename = "menu_item_#{@menu_item.id}_#{Time.now.to_i}#{ext}"
        public_url   = S3Uploader.upload(file, new_filename)
        @menu_item.update!(image_url: public_url)
      end

      render json: @menu_item, status: :created
    else
      Rails.logger.info "Failed to create => #{@menu_item.errors.full_messages.inspect}"
      render json: { errors: @menu_item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /menu_items/:id
  def update
    Rails.logger.info "=== MenuItemsController#update ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    @menu_item = MenuItem.find(params[:id])
    Rails.logger.info "Updating MenuItem => #{@menu_item.id}"

    # Assign categories before updating if category_ids param is given
    if params[:menu_item][:category_ids].present?
      @menu_item.category_ids = Array(params[:menu_item][:category_ids])
    end
    
    # Handle available_days as an array
    if params[:menu_item][:available_days].present?
      Rails.logger.info "Update - Available days param: #{params[:menu_item][:available_days].inspect}"
      Rails.logger.info "Update - Available days param class: #{params[:menu_item][:available_days].class}"
      
      available_days = Array(params[:menu_item][:available_days]).map(&:to_i)
      Rails.logger.info "Update - Processed available days: #{available_days.inspect}"
      
      @menu_item.available_days = available_days
    end

    if @menu_item.update(menu_item_params.except(:image))
      Rails.logger.info "Update success => #{@menu_item.inspect}"

      # Handle image if present
      file = menu_item_params[:image]
      if file.present? && file.respond_to?(:original_filename)
        ext = File.extname(file.original_filename)
        new_filename = "menu_item_#{@menu_item.id}_#{Time.now.to_i}#{ext}"
        public_url   = S3Uploader.upload(file, new_filename)
        @menu_item.update!(image_url: public_url)
      end

      render json: @menu_item
    else
      Rails.logger.info "Update failed => #{@menu_item.errors.full_messages.inspect}"
      render json: { errors: @menu_item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /menu_items/:id
  def destroy
    Rails.logger.info "=== MenuItemsController#destroy ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    menu_item = MenuItem.find(params[:id])
    Rails.logger.info "Destroying MenuItem => #{menu_item.id}, image_url: #{menu_item.image_url.inspect}"

    menu_item.destroy
    Rails.logger.info "Destroyed MenuItem => #{menu_item.id}"

    head :no_content
  end

  # (Optional) POST /menu_items/:id/upload_image
  def upload_image
    Rails.logger.info "=== MenuItemsController#upload_image ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    menu_item = MenuItem.find(params[:id])
    file = params[:image]
    unless file
      Rails.logger.info "No file param"
      return render json: { error: "No image file uploaded" }, status: :unprocessable_entity
    end

    ext = File.extname(file.original_filename)
    new_filename = "menu_item_#{menu_item.id}_#{Time.now.to_i}#{ext}"
    public_url   = S3Uploader.upload(file, new_filename)
    menu_item.update!(image_url: public_url)

    Rails.logger.info "menu_item updated => image_url: #{menu_item.image_url.inspect}"
    render json: menu_item, status: :ok
  end

  # POST /menu_items/:id/mark_as_damaged
  def mark_as_damaged
    Rails.logger.info "=== MenuItemsController#mark_as_damaged ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    menu_item = MenuItem.find(params[:id])

    unless menu_item.enable_stock_tracking
      return render json: { error: "Inventory tracking is not enabled for this item" }, status: :unprocessable_entity
    end

    quantity = params[:quantity].to_i
    reason = params[:reason].presence || "No reason provided"
    from_order = params[:order_id].present?

    if quantity <= 0
      return render json: { error: "Quantity must be greater than zero" }, status: :unprocessable_entity
    end

    # If this is coming from an order edit (through InventoryReversionDialog),
    # we need special handling to avoid duplicate inventory adjustments
    if from_order
      Rails.logger.info "Mark as damaged called from order edit - only updating damaged count"
      Rails.logger.info "INVENTORY DEBUG: Before increment_damaged_only - Item #{menu_item.id} (#{menu_item.name}) - Stock: #{menu_item.stock_quantity}, Damaged: #{menu_item.damaged_quantity}, Available: #{menu_item.available_quantity}"

      # Just increment the damaged count - the inventory adjustment will be handled by orders_controller
      if menu_item.increment_damaged_only(quantity, reason, current_user)
        Rails.logger.info "INVENTORY DEBUG: After increment_damaged_only - Item #{menu_item.id} (#{menu_item.name}) - Stock: #{menu_item.stock_quantity}, Damaged: #{menu_item.damaged_quantity}, Available: #{menu_item.available_quantity}"
        render json: menu_item
      else
        Rails.logger.error "INVENTORY DEBUG: Failed to increment_damaged_only"
        render json: { error: "Failed to mark items as damaged" }, status: :unprocessable_entity
      end
    else
      # Regular damaged marking (not from order edit)
      if menu_item.mark_as_damaged(quantity, reason, current_user)
        render json: menu_item
      else
        render json: { error: "Failed to mark items as damaged" }, status: :unprocessable_entity
      end
    end
  end

  # POST /menu_items/:id/update_stock
  def update_stock
    Rails.logger.info "=== MenuItemsController#update_stock ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    menu_item = MenuItem.find(params[:id])

    unless menu_item.enable_stock_tracking
      return render json: { error: "Inventory tracking is not enabled for this item" }, status: :unprocessable_entity
    end

    new_quantity = params[:stock_quantity].to_i
    reason_type = params[:reason_type] || "adjustment"
    reason_details = params[:reason_details].presence

    if new_quantity < 0
      return render json: { error: "Stock quantity cannot be negative" }, status: :unprocessable_entity
    end

    if menu_item.update_stock_quantity(new_quantity, reason_type, reason_details, current_user)
      render json: menu_item
    else
      render json: { error: "Failed to update stock quantity" }, status: :unprocessable_entity
    end
  end

  # GET /menu_items/:id/stock_audits
  def stock_audits
    Rails.logger.info "=== MenuItemsController#stock_audits ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    menu_item = MenuItem.find(params[:id])

    unless menu_item.enable_stock_tracking
      return render json: { error: "Inventory tracking is not enabled for this item" }, status: :unprocessable_entity
    end

    audits = menu_item.menu_item_stock_audits.order(created_at: :desc).limit(50)

    render json: audits
  end

  private

  def menu_item_params
    # category_ids => accept an array; remove single :category
    permitted_params = params.require(:menu_item).permit(
      :name,
      :description,
      :price,
      :cost_to_make,
      :available,
      :menu_id,
      :image_url,
      :advance_notice_hours,
      :image,
      :seasonal,
      :available_from,
      :available_until,
      :promo_label,
      :featured,
      :stock_status,
      :status_note,
      :enable_stock_tracking,
      :stock_quantity,
      :damaged_quantity,
      :low_stock_threshold,
      :category_ids,
      :available_days,
      category_ids: [],
      available_days: []
    )
    
    # Handle category_ids as a string
    if params[:menu_item][:category_ids].present? && params[:menu_item][:category_ids].is_a?(String)
      permitted_params[:category_ids] = params[:menu_item][:category_ids].split(',').map(&:to_i)
    end
    
    # Handle available_days as a string
    if params[:menu_item][:available_days].present?
      if params[:menu_item][:available_days].is_a?(String)
        # Split by comma and convert to integers
        permitted_params[:available_days] = params[:menu_item][:available_days].split(',').map(&:to_i)
      elsif !params[:menu_item][:available_days].is_a?(Array)
        # If it's a single value, convert it to an array
        permitted_params[:available_days] = [params[:menu_item][:available_days].to_i]
      end
    end
    
    permitted_params
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
