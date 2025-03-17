class MerchandiseVariantsController < ApplicationController
  before_action :set_merchandise_variant, only: [ :show, :update, :destroy, :add_stock, :reduce_stock ]
  before_action :authorize_request, except: [ :index, :show ]
  before_action :optional_authorize, only: [ :index, :show ]
  before_action :require_admin!, only: [ :add_stock, :reduce_stock ]

  # Mark all actions as public endpoints that don't require restaurant context
  def public_endpoint?
    true
  end

  # GET /merchandise_variants
  def index
    @variants = MerchandiseVariant.includes(:merchandise_item)

    # Filter by merchandise_item_id if provided
    if params[:merchandise_item_id].present?
      @variants = @variants.where(merchandise_item_id: params[:merchandise_item_id])
    end

    # Apply additional filters
    if params[:color].present?
      @variants = @variants.where(color: params[:color])
    end

    if params[:size].present?
      @variants = @variants.where(size: params[:size])
    end

    # Filter by stock status
    if params[:stock_status].present?
      case params[:stock_status]
      when "in_stock"
        @variants = @variants.where("stock_quantity > 0")
      when "out_of_stock"
        @variants = @variants.where(stock_quantity: 0)
      when "low_stock"
        @variants = @variants.where("stock_quantity > 0 AND stock_quantity <= COALESCE(low_stock_threshold, 5)")
      end
    end

    render json: @variants
  end

  # GET /merchandise_variants/1
  def show
    render json: @merchandise_variant
  end

  # POST /merchandise_variants
  def create
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    @merchandise_variant = MerchandiseVariant.new(merchandise_variant_params)

    if @merchandise_variant.save
      render json: @merchandise_variant, status: :created
    else
      render json: { errors: @merchandise_variant.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /merchandise_variants/1
  def update
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    if @merchandise_variant.update(merchandise_variant_params)
      render json: @merchandise_variant
    else
      render json: { errors: @merchandise_variant.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /merchandise_variants/1
  def destroy
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    @merchandise_variant.destroy
    head :no_content
  end

  # POST /merchandise_variants/batch_create
  def batch_create
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    merchandise_item_id = params[:merchandise_item_id]
    variants_params = params[:variants]

    unless merchandise_item_id.present? && variants_params.present? && variants_params.is_a?(Array)
      return render json: { error: "Invalid parameters" }, status: :unprocessable_entity
    end

    # Find the merchandise item
    merchandise_item = MerchandiseItem.find_by(id: merchandise_item_id)
    unless merchandise_item
      return render json: { error: "Merchandise item not found" }, status: :not_found
    end

    created_variants = []
    failed_variants = []

    # Start a transaction to ensure all variants are created or none
    ActiveRecord::Base.transaction do
      variants_params.each do |variant_param|
        variant = MerchandiseVariant.new(
          merchandise_item_id: merchandise_item_id,
          size: variant_param[:size],
          color: variant_param[:color],
          price_adjustment: variant_param[:price_adjustment] || 0,
          stock_quantity: variant_param[:stock_quantity] || 0
        )

        if variant.save
          created_variants << variant
        else
          failed_variants << {
            params: variant_param,
            errors: variant.errors.full_messages
          }
          raise ActiveRecord::Rollback
        end
      end
    end

    if failed_variants.empty?
      render json: {
        message: "All variants created successfully",
        variants: created_variants
      }, status: :created
    else
      render json: {
        error: "Failed to create variants",
        failed_variants: failed_variants
      }, status: :unprocessable_entity
    end
  end

  # POST /merchandise_variants/:id/add_stock
  def add_stock
    quantity = params[:quantity].to_i
    reason = params[:reason].presence || "Manual addition"

    if quantity <= 0
      return render json: { error: "Quantity must be greater than 0" }, status: :unprocessable_entity
    end

    new_quantity = @merchandise_variant.add_stock!(quantity, reason)

    render json: {
      message: "Successfully added #{quantity} to stock",
      new_quantity: new_quantity,
      variant: @merchandise_variant
    }
  end

  # POST /merchandise_variants/:id/reduce_stock
  def reduce_stock
    quantity = params[:quantity].to_i
    reason = params[:reason].presence || "Manual reduction"
    allow_negative = params[:allow_negative] == "true"

    if quantity <= 0
      return render json: { error: "Quantity must be greater than 0" }, status: :unprocessable_entity
    end

    begin
      new_quantity = @merchandise_variant.reduce_stock!(quantity, allow_negative)

      render json: {
        message: "Successfully reduced stock by #{quantity}",
        new_quantity: new_quantity,
        variant: @merchandise_variant
      }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end


  private

  def set_merchandise_variant
    @merchandise_variant = MerchandiseVariant.find(params[:id])
  end

  def merchandise_variant_params
    params.require(:merchandise_variant).permit(
      :merchandise_item_id,
      :size,
      :color,
      :price_adjustment,
      :stock_quantity,
      :sku,
      :low_stock_threshold
    )
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end

  def require_admin!
    unless is_admin?
      render json: { error: "Forbidden - Admin access required" }, status: :forbidden
    end
  end
end
