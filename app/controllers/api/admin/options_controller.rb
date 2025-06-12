class Api::Admin::OptionsController < ApplicationController
  include TenantScoped
  
  before_action :authenticate_user!
  before_action :require_staff_or_above!
  before_action :set_option, only: [:show, :update_stock, :mark_as_damaged, :stock_audits]

  # GET /api/admin/options/:id
  def show
    render json: @option.as_json(
      methods: [:additional_price_float, :available_quantity, :low_stock?, :out_of_stock?],
      include: { option_group: { only: [:id, :name, :enable_option_inventory, :low_stock_threshold] } }
    )
  end

  # PUT /api/admin/options/:id/stock
  def update_stock
    unless current_user.admin?
      return render json: { errors: ["Forbidden"] }, status: :forbidden
    end

    unless @option.option_group.enable_option_inventory?
      return render json: { 
        errors: ["Option inventory tracking is not enabled for this option group"] 
      }, status: :unprocessable_entity
    end

    new_quantity = params[:stock_quantity].to_i
    reason_type = params[:reason_type].presence || 'adjustment'
    reason_details = params[:reason_details].presence
    
    # Build the full reason string
    full_reason = if reason_details.present?
                    "#{reason_type.humanize}: #{reason_details}"
                  else
                    reason_type.humanize
                  end

    if new_quantity < 0
      return render json: { 
        errors: ["Stock quantity cannot be negative"] 
      }, status: :unprocessable_entity
    end

    if @option.update_stock_with_audit!(new_quantity, full_reason, user: current_user)
      # Update menu item status after option stock change
      @option.option_group.menu_item.update_stock_status!
      
      render json: @option.as_json(
        methods: [:additional_price_float, :available_quantity, :low_stock?, :out_of_stock?]
      )
    else
      render json: { 
        errors: ["Failed to update option stock"] 
      }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error("Failed to update option stock: #{e.message}")
    render json: { 
      errors: ["Failed to update option stock"] 
    }, status: :unprocessable_entity
  end

  # POST /api/admin/options/:id/mark_as_damaged
  def mark_as_damaged
    unless current_user.staff_or_above?
      return render json: { errors: ["Forbidden"] }, status: :forbidden
    end

    unless @option.option_group.enable_option_inventory?
      return render json: { 
        errors: ["Option inventory tracking is not enabled for this option group"] 
      }, status: :unprocessable_entity
    end

    quantity = params[:quantity].to_i
    reason = params[:reason].presence || "No reason provided"

    if quantity <= 0
      return render json: { 
        errors: ["Quantity must be greater than zero"] 
      }, status: :unprocessable_entity
    end

    if mark_option_as_damaged(quantity, reason)
      # Update menu item status after marking option as damaged
      @option.option_group.menu_item.update_stock_status!
      
      render json: @option.as_json(
        methods: [:additional_price_float, :available_quantity, :low_stock?, :out_of_stock?]
      )
    else
      render json: { 
        errors: ["Failed to mark option as damaged"] 
      }, status: :unprocessable_entity
    end
  end

  # GET /api/admin/options/:id/stock_audits
  def stock_audits
    unless current_user.admin?
      return render json: { errors: ["Forbidden"] }, status: :forbidden
    end

    unless @option.option_group.enable_option_inventory?
      return render json: { 
        errors: ["Option inventory tracking is not enabled for this option group"] 
      }, status: :unprocessable_entity
    end

    audits = @option.option_stock_audits.includes(:user, :order)
                   .order(created_at: :desc)
                   .limit(50)
                   .map do |audit|
      {
        id: audit.id,
        previous_quantity: audit.previous_quantity,
        new_quantity: audit.new_quantity,
        quantity_change: audit.quantity_change,
        reason: audit.reason,
        created_at: audit.created_at,
        user: audit.user ? { id: audit.user.id, name: audit.user.name } : nil,
        order: audit.order ? { id: audit.order.id, order_number: audit.order.order_number } : nil
      }
    end

    render json: audits
  end

  private

  def set_option
    @option = current_restaurant.options
                               .joins(option_group: { menu_item: :menu })
                               .find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: ["Option not found"] }, status: :not_found
  end

  def mark_option_as_damaged(quantity, reason)
    @option.transaction do
      # Create audit record for damaged item
      previous_damaged = @option.damaged_quantity
      new_damaged = previous_damaged + quantity

      @option.option_stock_audits.create!(
        previous_quantity: previous_damaged,
        new_quantity: new_damaged,
        reason: "Damaged: #{reason}",
        user: current_user
      )

      # Update the damaged quantity
      @option.update!(damaged_quantity: new_damaged)
      
      true
    end
  rescue => e
    Rails.logger.error("Failed to mark option as damaged: #{e.message}")
    false
  end

  def require_staff_or_above!
    unless current_user&.staff_or_above?
      render json: { errors: ["Forbidden"] }, status: :forbidden
    end
  end
end 