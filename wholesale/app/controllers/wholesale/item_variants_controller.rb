# app/controllers/wholesale/item_variants_controller.rb

module Wholesale
  class ItemVariantsController < ApplicationController
    # Allow guest access for stock checking
    skip_before_action :authorize_request, only: [:index, :show, :stock_status, :check_availability, :bulk_stock_check, :validate_combinations]
    before_action :optional_authorize, only: [:index, :show, :stock_status, :check_availability, :bulk_stock_check, :validate_combinations]
    before_action :find_item, only: [:index, :show, :stock_status, :check_availability, :bulk_stock_check, :validate_combinations]
    before_action :find_variant, only: [:show, :stock_status, :check_availability]
    
    # GET /wholesale/items/:item_id/variants
    # List all variants for an item
    def index
      unless @item.track_variants?
        return render_error("Item does not use variant tracking")
      end
      
      variants = @item.item_variants.includes(:item)
      
      render_success(
        variants: variants.map { |variant| variant_summary(variant) },
        item: {
          id: @item.id,
          name: @item.name,
          track_variants: @item.track_variants?
        },
        message: "Variants retrieved successfully"
      )
    end
    
    # GET /wholesale/items/:item_id/variants/:id
    # Get specific variant details
    def show
      render_success(
        variant: variant_detail(@variant),
        message: "Variant details retrieved successfully"
      )
    end
    
    # GET /wholesale/items/:item_id/variants/:id/stock_status
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
    
    # POST /wholesale/items/:item_id/variants/:id/check_availability
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
    
    # POST /wholesale/items/:item_id/variants/bulk_stock_check
    # Check stock status for multiple variants at once
    def bulk_stock_check
      variant_requests = params[:variants] || []
      
      if variant_requests.empty?
        return render_error("No variants specified")
      end
      
      results = []
      
      variant_requests.each do |variant_request|
        variant_key = variant_request[:variant_key] || variant_request['variant_key']
        quantity = (variant_request[:quantity] || variant_request['quantity'] || 1).to_i
        
        if variant_key.blank?
          results << {
            variant_key: nil,
            error: "Variant key is required"
          }
          next
        end
        
        variant = @item.item_variants.find_by(variant_key: variant_key)
        
        unless variant
          results << {
            variant_key: variant_key,
            error: "Variant not found"
          }
          next
        end
        
        available = variant.available_stock
        can_purchase = available >= quantity
        
        results << {
          variant_id: variant.id,
          variant_key: variant.variant_key,
          variant_name: variant.variant_name,
          requested_quantity: quantity,
          available_stock: available,
          can_purchase: can_purchase,
          max_quantity: available,
          is_active: variant.active?,
          stock_status: variant.stock_status
        }
      end
      
      render_success(
        results: results,
        item: {
          id: @item.id,
          name: @item.name
        },
        message: "Bulk stock check completed"
      )
    end
    
    # POST /wholesale/items/:item_id/variants/validate_combinations
    # Validate if option combinations are valid variants
    def validate_combinations
      combinations = params[:combinations] || []
      
      if combinations.empty?
        return render_error("No combinations specified")
      end
      
      unless @item.track_variants?
        return render_error("Item does not use variant tracking")
      end
      
      results = []
      
      combinations.each do |combination|
        selected_options = combination[:selected_options] || combination['selected_options'] || {}
        
        if selected_options.blank?
          results << {
            selected_options: selected_options,
            valid: false,
            error: "No options selected"
          }
          next
        end
        
        variant_key = @item.generate_variant_key(selected_options)
        variant = @item.find_variant_by_options(selected_options)
        
        if variant
          results << {
            selected_options: selected_options,
            valid: true,
            variant: {
              id: variant.id,
              variant_key: variant.variant_key,
              variant_name: variant.variant_name,
              available_stock: variant.available_stock,
              is_active: variant.active?,
              stock_status: variant.stock_status
            }
          }
        else
          variant_name = @item.generate_variant_name(selected_options)
          results << {
            selected_options: selected_options,
            valid: false,
            variant_key: variant_key,
            variant_name: variant_name,
            error: "#{variant_name || 'This combination'} is not available"
          }
        end
      end
      
      render_success(
        results: results,
        item: {
          id: @item.id,
          name: @item.name,
          track_variants: @item.track_variants?
        },
        message: "Combination validation completed"
      )
    end
    
    private
    
    def find_item
      @item = Wholesale::Item.find(params[:item_id])
      
      # Ensure item belongs to current restaurant
      unless @item.restaurant_id == current_restaurant.id
        render_error("Item not found", status: :not_found)
        return
      end
      
    rescue ActiveRecord::RecordNotFound
      render_error("Item not found", status: :not_found)
    end
    
    def find_variant
      @variant = @item.item_variants.find(params[:id])
      
    rescue ActiveRecord::RecordNotFound
      render_error("Variant not found", status: :not_found)
    end
    
    def variant_summary(variant)
      {
        id: variant.id,
        variant_key: variant.variant_key,
        variant_name: variant.variant_name,
        available_stock: variant.available_stock,
        stock_status: variant.stock_status,
        is_active: variant.active?,
        is_low_stock: variant.low_stock?,
        is_out_of_stock: variant.out_of_stock?
      }
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
