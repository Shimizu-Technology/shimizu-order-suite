module Wholesale
  module Admin
    # DEPRECATED: This controller is deprecated in favor of the new Option Groups system.
    # Use OptionGroupsController and OptionsController instead.
    # This controller is kept for backward compatibility only.
    class ItemVariantsController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_restaurant_context
      before_action :set_item
      before_action :set_variant, only: [:show, :update, :destroy]
      before_action :log_deprecation_warning
    
    # GET /wholesale/admin/items/:item_id/variants
    def index
      variants = @item.variants.active.includes(:wholesale_item)
      
      render_success(
        variants: variants.map { |variant| variant_json(variant) },
        item: {
          id: @item.id,
          name: @item.name,
          sku: @item.sku,
          has_variants: @item.has_options?
        }
      )
    end
    
    # GET /wholesale/admin/items/:item_id/variants/:id
    def show
      render_success(variant: variant_json(@variant))
    end
    
    # PATCH/PUT /wholesale/admin/items/:item_id/variants/:id
    def update
      if @variant.update(variant_params)
        render_success(
          variant: variant_json(@variant),
          message: 'Variant updated successfully!'
        )
      else
        render_error(
          'Failed to update variant',
          errors: @variant.errors.full_messages
        )
      end
    end
    
    # DELETE /wholesale/admin/items/:item_id/variants/:id
    def destroy
      if @variant.destroy
        render_success(message: 'Variant deleted successfully!')
      else
        render_error(
          'Failed to delete variant',
          errors: @variant.errors.full_messages
        )
      end
    end
    
    private
    
    def log_deprecation_warning
      Rails.logger.warn "DEPRECATED: ItemVariantsController is deprecated. Use OptionGroupsController instead. Called from #{request.path}"
    end
    
    def set_item
      @item = Wholesale::Item.joins(:fundraiser)
        .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
        .find_by(id: params[:item_id])
      render_not_found('Item not found') unless @item
    end
    
    def set_variant
      @variant = @item.variants.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_not_found('Variant not found')
    end
    
    def variant_params
      params.require(:variant).permit(
        :sku, :price_adjustment, :stock_quantity, :low_stock_threshold, :active
      )
    end
    
    def set_restaurant_context
      unless current_restaurant
        render_unauthorized('Restaurant context not set.')
      end
    end

    def variant_json(variant)
      {
        id: variant.id,
        sku: variant.sku,
        size: variant.size,
        color: variant.color,
        display_name: variant.display_name,
        full_display_name: variant.full_display_name,
        price_adjustment: variant.price_adjustment,
        final_price: variant.final_price,
        stock_quantity: variant.stock_quantity,
        low_stock_threshold: variant.low_stock_threshold,
        total_ordered: variant.total_ordered,
        total_revenue: variant.total_revenue,
        active: variant.active,
        can_purchase: variant.can_purchase?,
        created_at: variant.created_at,
        updated_at: variant.updated_at
      }
    end
    end
  end
end
