class Api::Admin::OptionGroupsController < ApplicationController
  before_action :set_current_tenant
  before_action :authorize_request
  before_action :require_admin!
  before_action :set_option_group, only: [:show, :configure_inventory, :inventory_status], if: -> { 
    action_name.in?(['show', 'configure_inventory']) || (action_name == 'inventory_status' && params[:id].present? && params[:menu_item_id].blank?)
  }
  before_action :set_menu_item, only: [:inventory_status], if: -> { params[:menu_item_id].present? }

  # GET /api/admin/option_groups/:id
  def show
    render json: @option_group.as_json(include: { 
      options: { 
        methods: [:additional_price_float, :available_quantity, :low_stock?, :out_of_stock?] 
      } 
    })
  end

  # PATCH /api/admin/option_groups/:id/configure_inventory
  def configure_inventory
    Rails.logger.info "=== CONFIGURE_INVENTORY ACTION STARTED ==="
    Rails.logger.info "Params: #{params.inspect}"
    Rails.logger.info "@option_group: #{@option_group.inspect}"
    Rails.logger.info "current_restaurant: #{current_restaurant&.id}"
    
    # Check if response was already performed by before_action (e.g., record not found)
    return if performed?
    
    unless current_user.admin?
      return render json: { errors: ["Forbidden"] }, status: :forbidden
    end

    # Safety check - if @option_group is nil, something went wrong
    unless @option_group
      Rails.logger.error "CONFIGURE_INVENTORY: @option_group is nil!"
      return render json: { errors: ["Option group not found"] }, status: :not_found
    end

    inventory_params = params.require(:option_group).permit(
      :enable_option_inventory, 
      :low_stock_threshold, 
      :tracking_priority
    )

    # Validate tracking priority constraints
    if inventory_params[:tracking_priority].to_i == 1 && inventory_params[:enable_option_inventory]
      existing_primary = @option_group.menu_item.option_groups
                                     .where(tracking_priority: 1, enable_option_inventory: true)
                                     .where.not(id: @option_group.id)
      
      if existing_primary.exists?
        return render json: { 
          errors: ["Only one option group per menu item can have primary tracking priority"] 
        }, status: :unprocessable_entity
      end
    end

    # Validate required group constraint
    if inventory_params[:enable_option_inventory] && @option_group.min_select == 0
      return render json: { 
        errors: ["Option inventory can only be enabled for required option groups (min_select > 0)"] 
      }, status: :unprocessable_entity
    end

    if @option_group.update(inventory_params)
      # Update menu item stock status if this became the primary tracking group
      if @option_group.primary_tracking_group?
        @option_group.menu_item.update_stock_status!
      end

      render json: @option_group.as_json(include: { 
        options: { 
          methods: [:additional_price_float, :available_quantity, :low_stock?, :out_of_stock?] 
        } 
      })
    else
      render json: { errors: @option_group.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/admin/option_groups/:id/inventory_status
  # GET /api/admin/menu_items/:menu_item_id/option_groups/inventory_status (collection)
  def inventory_status
    if @menu_item
      # Collection action: return all option groups for menu item
      option_groups = @menu_item.option_groups.includes(:options)
      
      render json: option_groups.map do |group|
        {
          id: group.id,
          name: group.name,
          min_select: group.min_select,
          max_select: group.max_select,
          enable_option_inventory: group.enable_option_inventory?,
          low_stock_threshold: group.low_stock_threshold,
          tracking_priority: group.tracking_priority,
          total_available_stock: group.total_available_stock,
          has_low_stock_options: group.has_low_stock_options?,
          all_options_out_of_stock: group.all_options_out_of_stock?,
          options: group.options.map do |option|
            {
              id: option.id,
              name: option.name,
              stock_quantity: option.stock_quantity,
              damaged_quantity: option.damaged_quantity,
              available_quantity: option.available_quantity,
              available: option.available_quantity > 0
            }
          end
        }
      end
    else
      # Member action: return single option group
      render json: {
        option_group_id: @option_group.id,
        enable_option_inventory: @option_group.enable_option_inventory?,
        primary_tracking_group: @option_group.primary_tracking_group?,
        total_available_stock: @option_group.total_available_stock,
        has_low_stock_options: @option_group.has_low_stock_options?,
        all_options_out_of_stock: @option_group.all_options_out_of_stock?,
        options: @option_group.options.map do |option|
          {
            id: option.id,
            name: option.name,
            stock_quantity: option.stock_quantity,
            damaged_quantity: option.damaged_quantity,
            available_quantity: option.available_quantity,
            is_low_stock: option.low_stock?,
            is_out_of_stock: option.out_of_stock?
          }
        end
      }
    end
  end

  private

  def set_option_group
    Rails.logger.info "=== SET_OPTION_GROUP BEFORE_ACTION STARTED ==="
    Rails.logger.info "Looking for option group ID: #{params[:id]} for restaurant: #{current_restaurant&.id}"
    Rails.logger.info "Action name: #{action_name}"
    
    # First check if the option group exists at all
    all_option_group = OptionGroup.find_by(id: params[:id])
    if all_option_group
      Rails.logger.info "Option group #{params[:id]} exists, belongs to menu_item: #{all_option_group.menu_item_id}, menu: #{all_option_group.menu_item.menu_id}, restaurant: #{all_option_group.menu_item.menu.restaurant_id}"
    else
      Rails.logger.info "Option group #{params[:id]} does not exist in database"
    end
    
    @option_group = OptionGroup.joins(menu_item: :menu)
                               .where(menus: { restaurant: current_restaurant })
                               .find(params[:id])
    Rails.logger.info "Successfully found option group: #{@option_group.id}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "=== OPTION GROUP NOT FOUND ==="
    Rails.logger.error "Option group #{params[:id]} not found for restaurant #{current_restaurant&.id}"
    render json: { errors: ["Option group not found"] }, status: :not_found
  end

  def set_menu_item
    @menu_item = MenuItem.joins(:menu)
                        .where(menus: { restaurant: current_restaurant })
                        .find(params[:menu_item_id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: ["Menu item not found"] }, status: :not_found
  end


end 