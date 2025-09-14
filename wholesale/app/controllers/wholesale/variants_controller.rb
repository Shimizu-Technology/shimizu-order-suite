# app/controllers/wholesale/variants_controller.rb

module Wholesale
  class VariantsController < ApplicationController
    # Allow guest access for stock checking
    skip_before_action :authorize_request, only: [:show, :stock_status, :check_availability]
    before_action :optional_authorize, only: [:show, :stock_status, :check_availability]
    before_action :find_variant, only: [:show, :stock_status, :check_availability]
    
    # GET /wholesale/variants/:id
    # Get variant details
    def show
      render_success(
        variant: variant_detail(@variant),
        message: "Variant details retrieved successfully"
      )
    end
    
    # GET /wholesale/variants/:id/stock_status
    # Get real-time stock status for a specific variant
    def stock_status
      render_success(
        stock_status: {
          variant_id: @variant.id,
          variant_key: @variant.variant_key,
          variant_name: @variant.variant_name,
          available_stock: @variant.available_stock,
          stock_quantity: @variant.stock_quantity,
          damaged_quantity: @variant.damaged_quantity,
          low_stock_threshold: @variant.low_stock_threshold,
          is_low_stock: @variant.low_stock?,
          is_out_of_stock: @variant.out_of_stock?,
          is_active: @variant.active?,
          stock_status: @variant.stock_status,
          last_updated: @variant.updated_at
        },
        message: "Stock status retrieved successfully"
      )
    end
    
    # POST /wholesale/variants/:id/check_availability
    # Check if variant is available for a specific quantity
    def check_availability
      quantity = params[:quantity].to_i
      
      if quantity <= 0
        return render_error("Quantity must be greater than 0")
      end
      
      available = @variant.available_stock
      can_purchase = available >= quantity
      
      render_success(
        availability: {
          variant_id: @variant.id,
          variant_key: @variant.variant_key,
          variant_name: @variant.variant_name,
          requested_quantity: quantity,
          available_stock: available,
          can_purchase: can_purchase,
          max_quantity: available,
          is_active: @variant.active?,
          stock_status: @variant.stock_status,
          message: can_purchase ? 
            "#{@variant.variant_name} is available" : 
            "#{@variant.variant_name} has insufficient stock (#{available} available)"
        },
        message: can_purchase ? "Available" : "Insufficient stock"
      )
    end
    
    private
    
    def find_variant
      @variant = Wholesale::ItemVariant.find(params[:id])
      
      # Ensure variant belongs to current restaurant
      unless @variant.item.restaurant_id == current_restaurant.id
        render_error("Variant not found", status: :not_found)
        return
      end
      
    rescue ActiveRecord::RecordNotFound
      render_error("Variant not found", status: :not_found)
    end
    
    def variant_detail(variant)
      {
        id: variant.id,
        variant_key: variant.variant_key,
        variant_name: variant.variant_name,
        stock_quantity: variant.stock_quantity,
        damaged_quantity: variant.damaged_quantity,
        available_stock: variant.available_stock,
        low_stock_threshold: variant.low_stock_threshold,
        active: variant.active?,
        stock_status: variant.stock_status,
        is_low_stock: variant.low_stock?,
        is_out_of_stock: variant.out_of_stock?,
        item: {
          id: variant.item.id,
          name: variant.item.name,
          track_variants: variant.item.track_variants?
        },
        created_at: variant.created_at,
        updated_at: variant.updated_at
      }
    end
  end
end
