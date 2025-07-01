# app/controllers/option_groups_controller.rb
class OptionGroupsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request
  before_action :ensure_tenant_context

  # GET /menu_items/:menu_item_id/option_groups
  def index
    option_groups = option_group_service.list_option_groups(params[:menu_item_id])

    render json: option_groups.as_json(
      include: {
        options: {
          methods: [ :additional_price_float ]
        }
      }
    )
  end

  # POST /menu_items/:menu_item_id/option_groups
  def create
    result = option_group_service.create_option_group(params[:menu_item_id], option_group_params)
    
    if result[:success]
      render json: result[:option_group].as_json(
        include: {
          options: {
            methods: [ :additional_price_float ]
          }
        }
      ), status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # PATCH /option_groups/:id
  def update
    result = option_group_service.update_option_group(params[:id], option_group_params)
    
    if result[:success]
      render json: result[:option_group].as_json(
        include: {
          options: {
            methods: [ :additional_price_float ]
          }
        }
      )
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # DELETE /option_groups/:id
  def destroy
    result = option_group_service.delete_option_group(params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /option_groups/:id/enable_inventory_tracking
  def enable_inventory_tracking
    option_group = find_option_group_with_tenant_scope(params[:id])
    return render json: { errors: ["Option group not found"] }, status: :not_found unless option_group

    result = OptionInventoryService.enable_option_tracking(option_group, current_user)
    
    if result[:success]
      render json: { 
        message: "Inventory tracking enabled successfully",
        option_group: result[:option_group].as_json(
          include: {
            options: {
              methods: [:additional_price_float, :available_stock, :in_stock?, :out_of_stock?]
            }
          }
        )
      }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # DELETE /option_groups/:id/disable_inventory_tracking
  def disable_inventory_tracking
    option_group = find_option_group_with_tenant_scope(params[:id])
    return render json: { errors: ["Option group not found"] }, status: :not_found unless option_group

    result = OptionInventoryService.disable_option_tracking(option_group, current_user)
    
    if result[:success]
      render json: { 
        message: "Inventory tracking disabled successfully",
        option_group: result[:option_group].as_json(
          include: {
            options: {
              methods: [:additional_price_float]
            }
          }
        )
      }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # PATCH /option_groups/:id/update_option_quantities
  def update_option_quantities
    option_group = find_option_group_with_tenant_scope(params[:id])
    return render json: { errors: ["Option group not found"] }, status: :not_found unless option_group

    quantities = params.require(:quantities).permit!.to_h
    reason = params[:reason] # Optional reason for the adjustment
    result = OptionInventoryService.update_option_quantities(option_group, quantities, current_user, reason)
    
    if result[:success]
      render json: { 
        message: "Option quantities updated successfully",
        option_group: option_group.reload.as_json(
          include: {
            options: {
              methods: [:additional_price_float, :available_stock, :in_stock?, :out_of_stock?]
            }
          }
        ),
        updated_options: result[:updated_options].map { |option|
          option.as_json(methods: [:additional_price_float, :available_stock, :in_stock?, :out_of_stock?])
        }
      }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # PATCH /option_groups/:id/update_single_option_quantity
  def update_single_option_quantity
    option_group = find_option_group_with_tenant_scope(params[:id])
    return render json: { errors: ["Option group not found"] }, status: :not_found unless option_group

    option_id = params.require(:option_id)
    quantity = params.require(:quantity)
    reason = params[:reason] # Optional reason for the adjustment
    
    result = OptionInventoryService.update_single_option_quantity(option_group, option_id, quantity, current_user, reason)
    
    if result[:success]
      render json: { 
        message: "Option quantity updated successfully",
        option_group: option_group.reload.as_json(
          include: {
            options: {
              methods: [:additional_price_float, :available_stock, :in_stock?, :out_of_stock?]
            }
          }
        ),
        menu_item: option_group.menu_item.reload.as_json(
          only: [:id, :name, :stock_quantity]
        )
      }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /option_groups/:id/mark_options_damaged
  def mark_options_damaged
    option_group = find_option_group_with_tenant_scope(params[:id])
    return render json: { errors: ["Option group not found"] }, status: :not_found unless option_group

    damage_quantities = params.require(:damage_quantities).permit!.to_h
    reason = params.require(:reason)
    
    result = OptionInventoryService.mark_options_damaged(option_group, damage_quantities, reason, current_user)
    
    if result[:success]
      render json: { 
        message: "Options marked as damaged successfully",
        damaged_options: result[:damaged_options].map { |option|
          option.as_json(methods: [:additional_price_float, :available_stock, :in_stock?, :out_of_stock?])
        }
      }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # GET /option_groups/:id/inventory_status
  def inventory_status
    option_group = find_option_group_with_tenant_scope(params[:id])
    return render json: { errors: ["Option group not found"] }, status: :not_found unless option_group

    render json: {
      inventory_tracking_enabled: option_group.inventory_tracking_enabled?,
      total_option_stock: option_group.total_option_stock,
      available_option_stock: option_group.available_option_stock,
      has_option_stock: option_group.has_option_stock?,
      options: option_group.options.map { |option|
        option.as_json(
          methods: [:additional_price_float, :available_stock, :in_stock?, :out_of_stock?, :low_stock?],
          only: [:id, :name, :stock_quantity, :damaged_quantity]
        )
      }
    }
  end

  # GET /option_groups/:id/audit_history
  def audit_history
    option_group = find_option_group_with_tenant_scope(params[:id])
    return render json: { errors: ["Option group not found"] }, status: :not_found unless option_group

    # Get audit records for all options in this group
    audits = OptionStockAudit.joins(:option)
                              .where(option: { option_group: option_group })
                              .includes(:option, :user, :order)
                              .order(created_at: :desc)
                              .limit(100)

    render json: audits.as_json(
      include: {
        option: { only: [:id, :name] },
        user: { only: [:id, :first_name, :last_name] },
        order: { only: [:id, :order_number] }
      },
      methods: [:quantity_change]
    )
  end

  # POST /option_groups/:id/force_synchronize_inventory
  def force_synchronize_inventory
    option_group = find_option_group_with_tenant_scope(params[:id])
    return render json: { errors: ["Option group not found"] }, status: :not_found unless option_group

    unless option_group.inventory_tracking_enabled?
      return render json: { error: "Inventory tracking is not enabled for this option group" }, status: :unprocessable_entity
    end

    menu_item = option_group.menu_item
    distribution_strategy = params[:distribution_strategy]&.to_sym || :proportional

    if OptionInventoryService.force_synchronize_inventory(menu_item, distribution_strategy)
      render json: { 
        success: true, 
        message: "Inventory synchronized successfully",
        menu_item_stock: menu_item.reload.stock_quantity,
        total_option_stock: option_group.reload.total_option_stock,
        option_breakdown: option_group.options.pluck(:id, :name, :stock_quantity).map do |id, name, stock|
          { option_id: id, name: name, stock: stock }
        end
      }
    else
      render json: { error: "Failed to synchronize inventory" }, status: :internal_server_error
    end
  end

  # GET /option_groups/:id/validate_synchronization
  def validate_synchronization
    option_group = find_option_group_with_tenant_scope(params[:id])
    return render json: { errors: ["Option group not found"] }, status: :not_found unless option_group

    unless option_group.inventory_tracking_enabled?
      return render json: { 
        synchronized: true, 
        message: "Inventory tracking is not enabled for this option group" 
      }
    end

    menu_item = option_group.menu_item
    is_synchronized = OptionInventoryService.validate_inventory_synchronization(menu_item)
    
    total_option_stock = option_group.total_option_stock
    menu_item_stock = menu_item.stock_quantity.to_i

    render json: {
      synchronized: is_synchronized,
      menu_item_stock: menu_item_stock,
      total_option_stock: total_option_stock,
      difference: menu_item_stock - total_option_stock,
      option_breakdown: option_group.options.pluck(:id, :name, :stock_quantity).map do |id, name, stock|
        { option_id: id, name: name, stock: stock }
      end
    }
  end

  private

  def option_group_params
    # Include enable_inventory_tracking in permitted params
    params.require(:option_group).permit(:name, :min_select, :max_select, :free_option_count, :enable_inventory_tracking)
  end

  def option_group_service
    @option_group_service ||= begin
      service = OptionGroupService.new(current_restaurant)
      service.current_user = current_user
      service
    end
  end

  # Find an option group with tenant scoping (copied from OptionGroupService)
  def find_option_group_with_tenant_scope(id)
    # First find the option group
    option_group = OptionGroup.find_by(id: id)
    return nil unless option_group
    
    # Then verify it belongs to a menu item in the current restaurant
    menu_item = option_group.menu_item
    return nil unless menu_item
    
    # Verify the menu item belongs to a menu in the current restaurant
    menu = menu_item.menu
    return nil unless menu
    
    # Finally, check if the menu belongs to the current restaurant
    return option_group if menu.restaurant_id == current_restaurant.id
    
    nil
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
end
