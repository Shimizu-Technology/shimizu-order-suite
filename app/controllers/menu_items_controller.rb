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
    items = menu_item_service.list_items(params)

    render json: items.as_json(
      include: {
        option_groups: {
          include: {
            options: {
              only: [ :id, :name, :available, :is_preselected, :is_available ],
              methods: [ :additional_price_float ]
            }
          }
        }
      }
    )
  end

  # GET /menu_items/:id
  def show
    begin
      item = menu_item_service.find_item(params[:id])
      
      render json: item.as_json(
        include: {
          option_groups: {
            include: {
              options: {
                only: [ :id, :name, :available, :is_preselected, :is_available ],
                methods: [ :additional_price_float ]
              }
            }
          }
        }
      )
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Item not found" }, status: :not_found
    end
  end

  # POST /menu_items
  def create
    Rails.logger.info "=== MenuItemsController#create ==="
    
    result = menu_item_service.create_item(
      menu_item_params.except(:image),
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
      menu_item_params.except(:image),
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
