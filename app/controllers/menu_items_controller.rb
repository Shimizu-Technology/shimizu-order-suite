class MenuItemsController < ApplicationController
  include TenantIsolation
  
  # 1) For index & show, optional_authorize => public can see
  before_action :optional_authorize, only: [ :index, :show ]

  # 2) For other actions, require token + admin
  before_action :authorize_request, except: [ :index, :show ]
  
  # Ensure tenant context for all actions
  before_action :ensure_tenant_context
  
  # Override global_access_permitted to allow public access to index and show
  def global_access_permitted?
    action_name.in?(["index", "show"])
  end

  # GET /menu_items
  def index
    Rails.logger.info "[MenuItemsController#index] Params: #{params.inspect}"
    items = menu_item_service.list_items(params)

    # Optimize response based on view_type and include_option_groups parameter
    case params[:view_type]
    when 'list'
      # Minimal data for listings - but check if option groups are explicitly requested
      if params[:include_option_groups].present? && params[:include_option_groups].to_s.downcase == 'true'
        render json: items.as_json(
          only: [:id, :name, :price, :image_url, :featured, :seasonal, :hidden, 
                 :category_ids, :menu_id, :available_from, :available_until, 
                 :available_days, :stock_quantity, :damaged_quantity, :stock_status],
          include: {
            option_groups: {
              include: {
                options: {
                  only: [ :id, :name, :available, :is_preselected, :is_available, :stock_quantity, :damaged_quantity ],
                  methods: [ :additional_price_float, :available_stock, :in_stock?, :out_of_stock?, :low_stock?, :inventory_tracking_enabled? ]
                }
              }
            }
          }
        )
      else
        render json: items.as_json(
          only: [:id, :name, :price, :image_url, :featured, :seasonal, :hidden, 
                 :category_ids, :menu_id, :available_from, :available_until, 
                 :available_days, :stock_quantity, :damaged_quantity, :stock_status]
        )
      end
    when 'admin'
      # Full data for admin views - include option groups if explicitly requested
      if params[:include_option_groups].present? && params[:include_option_groups].to_s.downcase == 'true'
        render json: items.as_json(
          methods: [:available_quantity],
          include: {
            option_groups: {
              include: {
                options: {
                  only: [ :id, :name, :available, :is_preselected, :is_available, :stock_quantity, :damaged_quantity ],
                  methods: [ :additional_price_float, :available_stock, :in_stock?, :out_of_stock?, :low_stock?, :inventory_tracking_enabled? ]
                }
              }
            }
          }
        )
      else
        # Original admin behavior without option groups for performance
        render json: items.as_json(
          methods: [:available_quantity]
        )
      end
    else
      # Full data including options (default)
      render json: items.as_json(
        include: {
          option_groups: {
            include: {
              options: {
                only: [ :id, :name, :available, :is_preselected, :is_available, :stock_quantity, :damaged_quantity ],
                methods: [ :additional_price_float, :available_stock, :in_stock?, :out_of_stock?, :low_stock?, :inventory_tracking_enabled? ]
              }
            }
          }
        },
        methods: [:available_quantity]
      )
    end
  end

  # GET /menu_items/:id
  def show
    begin
      item = menu_item_service.find_item(params[:id])
      
      # Enhanced JSON response to include option inventory information
      render json: item.as_json(
        include: {
          option_groups: {
            include: {
              options: {
                only: [ :id, :name, :available, :is_preselected, :is_available, :stock_quantity, :damaged_quantity ],
                methods: [ :additional_price_float, :available_stock, :in_stock?, :out_of_stock?, :low_stock?, :inventory_tracking_enabled? ]
              }
            },
            methods: [:inventory_tracking_enabled?, :total_option_stock, :available_option_stock, :has_option_stock?]
          }
        },
        methods: [
          :has_option_inventory_tracking?, 
          :uses_option_level_inventory?, 
          :effective_available_quantity, 
          :effectively_out_of_stock?,
          :option_inventory_matches_item_inventory?
        ]
      )
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Item not found" }, status: :not_found
    end
  end

  # POST /menu_items
  def create
    Rails.logger.info "=== MenuItemsController#create ==="
    
    result = menu_item_service.create_item(
      menu_item_params,
      params[:menu_item][:category_ids],
      params[:menu_item][:available_days]
    )
    
    if result[:success]
      Rails.logger.info "Created MenuItem => #{result[:menu_item].inspect}"
      render json: result[:menu_item], status: :created
    else
      Rails.logger.info "Failed to create => #{result[:errors].inspect}"
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # PATCH/PUT /menu_items/:id
  def update
    Rails.logger.info "=== MenuItemsController#update ==="
    
    # Log the full params for debugging
    Rails.logger.info "FULL PARAMS: #{params.to_json}"
    Rails.logger.info "MENU ITEM PARAMS: #{menu_item_params.inspect}"
    
    result = menu_item_service.update_item(
      params[:id],
      menu_item_params,
      params[:menu_item][:category_ids],
      params[:menu_item][:available_days]
    )
    
    if result[:success]
      Rails.logger.info "Update success => #{result[:menu_item].inspect}"
      render json: result[:menu_item]
    else
      Rails.logger.info "Update failed => #{result[:errors].inspect}"
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # DELETE /menu_items/:id
  def destroy
    Rails.logger.info "=== MenuItemsController#destroy ==="
    
    result = menu_item_service.delete_item(params[:id])
    
    if result[:success]
      Rails.logger.info "Destroyed MenuItem => #{params[:id]}"
      head :no_content
    else
      Rails.logger.info "Failed to destroy MenuItem => #{result[:errors].inspect}"
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # (Optional) POST /menu_items/:id/upload_image
  def upload_image
    Rails.logger.info "=== MenuItemsController#upload_image ==="
    
    result = menu_item_service.upload_image(params[:id], params[:image])
    
    if result[:success]
      Rails.logger.info "menu_item updated => image_url: #{result[:menu_item].image_url.inspect}"
      render json: result[:menu_item], status: :ok
    else
      Rails.logger.info "Failed to upload image => #{result[:errors].inspect}"
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /menu_items/:id/mark_as_damaged
  def mark_as_damaged
    Rails.logger.info "=== MenuItemsController#mark_as_damaged ==="
    
    menu_item = menu_item_service.find_item(params[:id])
    return render json: { errors: ["Menu item not found"] }, status: :not_found unless menu_item
    
    # Check if this menu item uses option-level inventory
    if menu_item.uses_option_level_inventory?
      # For option-level inventory, delegate to OptionInventoryService
      return render json: { 
        errors: ["This menu item uses option-level inventory tracking. Please mark individual options as damaged instead."],
        suggestion: "Use POST /options/:option_id/mark_damaged for individual options or POST /option_groups/:group_id/mark_options_damaged for bulk operations."
      }, status: :unprocessable_entity
    end
    
    # For regular inventory, use the existing service
    result = menu_item_service.mark_as_damaged(params[:id], params)
    
    if result[:success]
      if params[:order_id].present?
        Rails.logger.info "INVENTORY DEBUG: After increment_damaged_only - Item #{params[:id]} - Success"
      end
      render json: result[:menu_item]
    else
      Rails.logger.error "Failed to mark items as damaged: #{result[:errors].inspect}"
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /menu_items/:id/update_stock
  def update_stock
    Rails.logger.info "=== MenuItemsController#update_stock ==="
    
    menu_item = menu_item_service.find_item(params[:id])
    return render json: { errors: ["Menu item not found"] }, status: :not_found unless menu_item
    
    # Check if this menu item uses option-level inventory
    if menu_item.uses_option_level_inventory?
      # For option-level inventory, delegate to OptionInventoryService
      return render json: { 
        errors: ["This menu item uses option-level inventory tracking. Please update individual option quantities instead."],
        suggestion: "Use PATCH /options/:option_id/update_stock for individual options or PATCH /option_groups/:group_id/update_option_quantities for bulk updates."
      }, status: :unprocessable_entity
    end
    
    # For regular inventory, use the existing service
    result = menu_item_service.update_stock(params[:id], params)
    
    if result[:success]
      render json: result[:menu_item]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # GET /menu_items/:id/stock_audits
  def stock_audits
    Rails.logger.info "=== MenuItemsController#stock_audits ==="
    
    result = menu_item_service.get_stock_audits(params[:id])
    
    if result[:success]
      render json: result[:audits]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # POST /menu_items/:id/copy
  def copy
    Rails.logger.info "=== MenuItemsController#copy ==="
    
    result = menu_item_service.copy_item(params[:id], params)
    
    if result[:success]
      Rails.logger.info "Created copied MenuItem => #{result[:menu_item].inspect}"
      render json: result[:menu_item], status: :created
    else
      Rails.logger.info "Failed to copy menu item => #{result[:errors].inspect}"
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /menu_items/:id/force_synchronize_option_inventory
  def force_synchronize_option_inventory
    menu_item = menu_item_service.find_item(params[:id])
    return render json: { errors: ["Menu item not found"] }, status: :not_found unless menu_item

    unless menu_item.uses_option_level_inventory?
      return render json: { error: "This menu item does not use option-level inventory tracking" }, status: :unprocessable_entity
    end

    distribution_strategy = params[:distribution_strategy]&.to_sym || :proportional

    if OptionInventoryService.force_synchronize_inventory(menu_item, distribution_strategy)
      tracking_group = menu_item.option_inventory_tracking_group
      render json: { 
        success: true, 
        message: "Option inventory synchronized successfully",
        menu_item_stock: menu_item.reload.stock_quantity,
        total_option_stock: tracking_group.reload.total_option_stock,
        option_breakdown: tracking_group.options.pluck(:id, :name, :stock_quantity).map do |id, name, stock|
          { option_id: id, name: name, stock: stock }
        end
      }
    else
      render json: { error: "Failed to synchronize option inventory" }, status: :internal_server_error
    end
  end

  # GET /menu_items/:id/validate_option_inventory_sync
  def validate_option_inventory_sync
    menu_item = menu_item_service.find_item(params[:id])
    return render json: { errors: ["Menu item not found"] }, status: :not_found unless menu_item

    unless menu_item.uses_option_level_inventory?
      return render json: { 
        synchronized: true, 
        message: "This menu item does not use option-level inventory tracking" 
      }
    end

    is_synchronized = OptionInventoryService.validate_inventory_synchronization(menu_item)
    tracking_group = menu_item.option_inventory_tracking_group
    
    total_option_stock = tracking_group.total_option_stock
    menu_item_stock = menu_item.stock_quantity.to_i

    render json: {
      synchronized: is_synchronized,
      menu_item_stock: menu_item_stock,
      total_option_stock: total_option_stock,
      difference: menu_item_stock - total_option_stock,
      option_breakdown: tracking_group.options.pluck(:id, :name, :stock_quantity).map do |id, name, stock|
        { option_id: id, name: name, stock: stock }
      end
    }
  end

  # GET /menu_items/audit_inventory_synchronization
  def audit_inventory_synchronization
    restaurant_id = current_restaurant&.id
    issues = OptionInventoryService.audit_inventory_synchronization(restaurant_id)
    
    render json: {
      total_issues: issues.count,
      synchronized: issues.empty?,
      issues: issues
    }
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
      :hidden,
      category_ids: [],
      available_days: []
    )
    
    # Handle category_ids as a string
    if params[:menu_item][:category_ids].present? && params[:menu_item][:category_ids].is_a?(String)
      permitted_params[:category_ids] = params[:menu_item][:category_ids].split(',').map(&:to_i)
    end
    
    # Handle available_days as a string
    if params[:menu_item].has_key?(:available_days)
      if params[:menu_item][:available_days].blank?
        # If available_days is explicitly set to blank or empty array, clear it
        permitted_params[:available_days] = []
      elsif params[:menu_item][:available_days].is_a?(String)
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
  
  def menu_item_service
    @menu_item_service ||= begin
      service = MenuItemService.new(current_restaurant)
      service.current_user = current_user
      service
    end
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
end
