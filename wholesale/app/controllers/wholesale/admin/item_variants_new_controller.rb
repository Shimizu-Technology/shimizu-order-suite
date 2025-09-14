module Wholesale
  module Admin
    class ItemVariantsNewController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_restaurant_context
      before_action :set_item
      before_action :set_variant, only: [:show]
      
      # GET /wholesale/admin/items/:item_id/variants
      def index
        unless @item.track_variants?
          return render_error("Item does not use variant tracking")
        end
        
        variants = @item.item_variants.includes(:wholesale_item)
        
        render_success(
          variants: variants.map { |variant| variant_json(variant) },
          item: {
            id: @item.id,
            name: @item.name,
            track_variants: @item.track_variants?
          },
          message: "Variants retrieved successfully"
        )
      end
      
      # GET /wholesale/admin/items/:item_id/variants/:id
      def show
        render_success(
          variant: variant_json(@variant),
          message: "Variant details retrieved successfully"
        )
      end
      
      private
      
      def set_item
        @item = Wholesale::Item.joins(:fundraiser)
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .find_by(id: params[:item_id])
        render_not_found('Item not found') unless @item
      end
      
      def set_variant
        @variant = @item.item_variants.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Variant not found')
      end
      
      def set_restaurant_context
        unless current_restaurant
          render_unauthorized('Restaurant context not set.')
        end
      end

      def variant_json(variant)
        {
          id: variant.id,
          variant_key: variant.variant_key,
          variant_name: variant.variant_name,
          stock_quantity: variant.stock_quantity,
          damaged_quantity: variant.damaged_quantity,
          low_stock_threshold: variant.low_stock_threshold,
          available_stock: variant.available_stock,
          active: variant.active,
          stock_status: variant.stock_status,
          in_stock: variant.in_stock?,
          out_of_stock: variant.out_of_stock?,
          low_stock: variant.low_stock?,
          created_at: variant.created_at,
          updated_at: variant.updated_at
        }
      end
    end
  end
end
