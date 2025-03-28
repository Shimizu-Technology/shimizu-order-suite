# app/controllers/options_controller.rb
class OptionsController < ApplicationController
  before_action :authorize_request
  before_action :set_option, only: [ :update, :destroy, :update_inventory, :stock_audits, :mark_as_damaged ]

  # Mark all actions as public endpoints that don't require restaurant context
  def public_endpoint?
    true
  end

  # POST /option_groups/:option_group_id/options
  def create
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    option_group = OptionGroup.find(params[:option_group_id])
    option = option_group.options.build(option_params)

    if option.save
      render json: option.as_json(methods: [ :additional_price_float ]), status: :created
    else
      render json: { errors: option.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /options/:id
  def update
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    if @option.update(option_params)
      render json: @option.as_json(methods: [ :additional_price_float ])
    else
      render json: { errors: @option.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /options/:id
  def destroy
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    @option.destroy
    head :no_content
  end

  # PATCH /options/:id/update_inventory
  def update_inventory
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    
    previous_quantity = @option.stock_quantity
    
    if @option.update(inventory_params)
      @option.update_stock_status!
      
      # Create audit record if stock quantity changed
      if @option.enable_stock_tracking && previous_quantity != @option.stock_quantity
        OptionStockAudit.create_stock_record(
          @option,
          @option.stock_quantity,
          :adjustment,
          "Manual inventory update",
          current_user
        )
      end
      
      render json: @option
    else
      render json: { errors: @option.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  # GET /options/:id/stock_audits
  def stock_audits
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    
    audits = @option.stock_audits.order(created_at: :desc).limit(50)
    render json: audits
  end
  
  # POST /options/:id/mark_as_damaged
  def mark_as_damaged
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    
    quantity = params[:quantity].to_i
    reason = params[:reason]
    
    if quantity <= 0
      return render json: { error: "Quantity must be greater than zero" }, status: :unprocessable_entity
    end
    
    if reason.blank?
      return render json: { error: "Reason is required" }, status: :unprocessable_entity
    end
    
    if @option.mark_as_damaged(quantity, reason, current_user)
      render json: @option
    else
      render json: { error: "Failed to mark items as damaged" }, status: :unprocessable_entity
    end
  end

  private

  def set_option
    @option = Option.find(params[:id])
  end

  def option_params
    # Adjust based on your actual Option columns
    params.require(:option).permit(:name, :additional_price, :available, :is_preselected,
                                  :enable_stock_tracking, :stock_quantity, :damaged_quantity,
                                  :low_stock_threshold, :stock_status)
  end
  
  def inventory_params
    params.require(:option).permit(:enable_stock_tracking, :stock_quantity, :damaged_quantity, :low_stock_threshold)
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
