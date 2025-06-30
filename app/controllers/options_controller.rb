# app/controllers/options_controller.rb
class OptionsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request
  before_action :ensure_tenant_context

  # POST /option_groups/:option_group_id/options
  def create
    result = option_service.create_option(params[:option_group_id], option_params)
    
    if result[:success]
      render json: result[:option].as_json(methods: [ :additional_price_float ]), status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # PATCH /options/:id
  def update
    result = option_service.update_option(params[:id], option_params)
    
    if result[:success]
      render json: result[:option].as_json(methods: [ :additional_price_float ])
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # DELETE /options/:id
  def destroy
    result = option_service.delete_option(params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # PATCH /options/batch
  def batch_update
    result = option_service.batch_update_options(batch_params[:option_ids], batch_params[:updates])
    
    if result[:success]
      render json: { message: "#{result[:updated_count]} options updated successfully" }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # PATCH /options/batch_update_positions
  def batch_update_positions
    # Extract positions data from params
    positions_data = params.require(:positions).map do |item|
      {
        id: item[:id],
        position: item[:position]
      }
    end
    
    result = option_service.batch_update_positions(positions_data)
    
    if result[:success]
      render json: { message: "#{result[:updated_count]} options reordered successfully" }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # GET /options/:id/inventory_status
  def inventory_status
    option = find_option_with_tenant_scope(params[:id])
    return render json: { errors: ["Option not found"] }, status: :not_found unless option

    render json: {
      inventory_tracking_enabled: option.inventory_tracking_enabled?,
      stock_quantity: option.stock_quantity,
      damaged_quantity: option.damaged_quantity,
      available_stock: option.available_stock,
      in_stock: option.in_stock?,
      out_of_stock: option.out_of_stock?,
      low_stock: option.low_stock?
    }
  end

  # PATCH /options/:id/update_stock
  def update_stock
    option = find_option_with_tenant_scope(params[:id])
    return render json: { errors: ["Option not found"] }, status: :not_found unless option

    return render json: { errors: ["Inventory tracking not enabled for this option"] }, status: :unprocessable_entity unless option.inventory_tracking_enabled?

    new_quantity = params.require(:stock_quantity).to_i
    reason = params[:reason] || "Manual stock update"

    begin
      ActiveRecord::Base.transaction do
        option.update!(stock_quantity: new_quantity)
        
        # Create audit record
        OptionStockAudit.create_stock_record(option, new_quantity, :adjustment, "#{reason} (#{option.name})", current_user)
        
        # Sync menu item inventory if needed
        if option.option_group.inventory_tracking_enabled?
          option_group = option.option_group
          total_option_stock = option_group.total_option_stock
          menu_item = option_group.menu_item
          
          if menu_item.stock_quantity != total_option_stock
            menu_item.update!(stock_quantity: total_option_stock)
          end
        end
      end

      render json: { 
        message: "Option stock updated successfully",
        option: option.as_json(methods: [:additional_price_float, :available_stock, :in_stock?, :out_of_stock?])
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    rescue => e
      render json: { errors: ["Failed to update stock: #{e.message}"] }, status: :internal_server_error
    end
  end

  # POST /options/:id/mark_damaged
  def mark_damaged
    option = find_option_with_tenant_scope(params[:id])
    return render json: { errors: ["Option not found"] }, status: :not_found unless option

    return render json: { errors: ["Inventory tracking not enabled for this option"] }, status: :unprocessable_entity unless option.inventory_tracking_enabled?

    quantity = params.require(:quantity).to_i
    reason = params.require(:reason)

    begin
      ActiveRecord::Base.transaction do
        if option.mark_damaged!(quantity)
          # Create audit record
          OptionStockAudit.create_damaged_record(option, quantity, reason, current_user)
          
          render json: { 
            message: "Option marked as damaged successfully",
            option: option.as_json(methods: [:additional_price_float, :available_stock, :in_stock?, :out_of_stock?])
          }
        else
          render json: { errors: ["Cannot mark #{quantity} items as damaged. Available stock: #{option.available_stock}"] }, status: :unprocessable_entity
        end
      end
    rescue => e
      render json: { errors: ["Failed to mark as damaged: #{e.message}"] }, status: :internal_server_error
    end
  end

  # POST /options/:id/restock
  def restock
    option = find_option_with_tenant_scope(params[:id])
    return render json: { errors: ["Option not found"] }, status: :not_found unless option

    return render json: { errors: ["Inventory tracking not enabled for this option"] }, status: :unprocessable_entity unless option.inventory_tracking_enabled?

    quantity = params.require(:quantity).to_i
    reason = params[:reason] || "Restock"

    begin
      ActiveRecord::Base.transaction do
        new_stock = option.stock_quantity + quantity
        option.update!(stock_quantity: new_stock)
        
        # Create audit record
        OptionStockAudit.create_stock_record(option, new_stock, :restock, "#{reason} (#{option.name})", current_user)
        
        # Sync menu item inventory if needed
        if option.option_group.inventory_tracking_enabled?
          option_group = option.option_group
          total_option_stock = option_group.total_option_stock
          menu_item = option_group.menu_item
          
          if menu_item.stock_quantity != total_option_stock
            menu_item.update!(stock_quantity: total_option_stock)
          end
        end
      end

      render json: { 
        message: "Option restocked successfully",
        option: option.as_json(methods: [:additional_price_float, :available_stock, :in_stock?, :out_of_stock?])
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    rescue => e
      render json: { errors: ["Failed to restock: #{e.message}"] }, status: :internal_server_error
    end
  end

  # GET /options/:id/audit_history
  def audit_history
    option = find_option_with_tenant_scope(params[:id])
    return render json: { errors: ["Option not found"] }, status: :not_found unless option

    audits = option.option_stock_audits
                   .includes(:user, :order)
                   .order(created_at: :desc)
                   .limit(50)

    render json: audits.as_json(
      include: {
        user: { only: [:id, :first_name, :last_name] },
        order: { only: [:id, :order_number] }
      },
      methods: [:quantity_change]
    )
  end

  private

  def option_params
    # Include stock_quantity and damaged_quantity in permitted params
    params.require(:option).permit(:name, :additional_price, :available, :is_preselected, :is_available, :position, :stock_quantity, :damaged_quantity)
  end

  def batch_params
    params.permit(option_ids: [], updates: [:is_available, :position])
  end

  def option_service
    @option_service ||= begin
      service = OptionService.new(current_restaurant)
      service.current_user = current_user
      service
    end
  end

  # Find an option with tenant scoping (copied from OptionService)
  def find_option_with_tenant_scope(id)
    # First find the option
    option = Option.find_by(id: id)
    return nil unless option
    
    # Then verify it belongs to an option group in the current restaurant
    option_group = option.option_group
    return nil unless option_group
    
    # Then verify it belongs to a menu item in the current restaurant
    menu_item = option_group.menu_item
    return nil unless menu_item
    
    # Verify the menu item belongs to a menu in the current restaurant
    menu = menu_item.menu
    return nil unless menu
    
    # Finally, check if the menu belongs to the current restaurant
    return option if menu.restaurant_id == current_restaurant.id
    
    nil
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
end
