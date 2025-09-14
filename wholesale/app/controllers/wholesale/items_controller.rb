# app/controllers/wholesale/items_controller.rb

module Wholesale
  class ItemsController < ApplicationController
    # Skip authentication for public browsing of items
    skip_before_action :authorize_request, only: [:index, :show]
    before_action :find_fundraiser_by_slug
    before_action :find_item, only: [:show]
    
    # GET /wholesale/fundraisers/:fundraiser_slug/items
    # List all active items for a specific fundraiser
    def index
      return unless @fundraiser
      
      @items = @fundraiser.items
        .active
        .includes(:item_images)
        .by_sort_order
      
      # Optional filtering
      @items = @items.in_stock if params[:in_stock_only] == 'true'
      
      render_success(
        items: @items.map { |item| item_summary(item) },
        fundraiser: {
          id: @fundraiser.id,
          name: @fundraiser.name,
          slug: @fundraiser.slug
        },
        message: "Items retrieved successfully"
      )
    end
    
    # GET /wholesale/fundraisers/:fundraiser_slug/items/:id
    # Get detailed information about a specific item
    def show
      return unless @item
      
      render_success(
        item: item_detail(@item),
        fundraiser: {
          id: @fundraiser.id,
          name: @fundraiser.name,
          slug: @fundraiser.slug
        },
        message: "Item details retrieved successfully"
      )
    end
    
    # GET /wholesale/items/:id
    # Get item details by ID (alternative endpoint)
    def show_by_id
      @item = Wholesale::Item
        .joins(:fundraiser)
        .where(fundraiser: { restaurant: current_restaurant })
        .includes(:item_images, :fundraiser)
        .find(params[:id])
      
      @fundraiser = @item.fundraiser
      
      render_success(
        item: item_detail(@item),
        fundraiser: {
          id: @fundraiser.id,
          name: @fundraiser.name,
          slug: @fundraiser.slug
        },
        message: "Item details retrieved successfully"
      )
    rescue ActiveRecord::RecordNotFound
      render_not_found("Item not found")
    end
    
    # POST /wholesale/items/:id/check_availability
    # Check if item is available for given quantity
    def check_availability
      @item = Wholesale::Item
        .joins(:fundraiser)
        .where(fundraiser: { restaurant: current_restaurant })
        .find(params[:id])
      
      quantity = params[:quantity].to_i
      
      if quantity <= 0
        return render_error("Quantity must be greater than 0")
      end
      
      available = @item.can_purchase?(quantity)
      
      render_success(
        available: available,
        requested_quantity: quantity,
        available_quantity: @item.track_inventory? ? @item.available_quantity : "unlimited",
        stock_status: @item.stock_status,
        message: available ? "Item is available" : "Insufficient stock"
      )
    rescue ActiveRecord::RecordNotFound
      render_not_found("Item not found")
    end
    
    private
    
    def find_item
      @item = @fundraiser.items.active.includes(:item_images).find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_not_found("Item not found")
      nil
    end
    
    # Summary format for item listing
    def item_summary(item)
      {
        id: item.id,
        name: item.name,
        description: item.description,
        sku: item.sku,
        price: item.price,
        price_cents: item.price_cents,
        position: item.position,
        sort_order: item.sort_order,
        options: item.options,
        
        # Availability
        active: item.active?,
        track_inventory: item.track_inventory?,
        track_variants: item.track_variants?,
        uses_option_level_inventory: item.uses_option_level_inventory?,
        in_stock: item.in_stock?,
        stock_status: item.stock_status,
        available_quantity: item.track_inventory? ? item.available_quantity : nil,
        effective_available_quantity: item.effective_available_quantity,
        
        # Primary image only for summary
        primary_image_url: item.primary_image_url,
        
        # Basic statistics
        total_ordered: item.total_ordered_quantity,
        
        # Option Groups (new system)
        option_groups: item.option_groups.includes(:options).order(:position).map do |group|
          {
            id: group.id,
            name: group.name,
            min_select: group.min_select,
            max_select: group.max_select,
            required: group.required,
            position: group.position,
            enable_inventory_tracking: group.enable_inventory_tracking,
            options: group.options.order(:position).map do |option|
              {
                id: option.id,
                name: option.name,
                additional_price: option.additional_price.to_f,
                available: option.available,
                position: option.position,
                stock_quantity: option.stock_quantity,
                damaged_quantity: option.damaged_quantity,
                low_stock_threshold: option.low_stock_threshold
              }
            end
          }
        end,
        
        # Item Variants (for variant-level inventory tracking)
        item_variants: item.track_variants? ? item.item_variants.map do |variant|
          {
            id: variant.id,
            variant_key: variant.variant_key,
            variant_name: variant.variant_name,
            stock_quantity: variant.stock_quantity,
            damaged_quantity: variant.damaged_quantity,
            low_stock_threshold: variant.low_stock_threshold,
            active: variant.active,
            available_stock: variant.available_stock,
            in_stock: variant.in_stock?,
            out_of_stock: variant.out_of_stock?,
            low_stock: variant.low_stock?
          }
        end : [],
        
        created_at: item.created_at,
        updated_at: item.updated_at
      }
    end
    
    # Detailed format for specific item view
    def item_detail(item)
      {
        id: item.id,
        name: item.name,
        description: item.description,
        sku: item.sku,
        price: item.price,
        price_cents: item.price_cents,
        position: item.position,
        sort_order: item.sort_order,
        options: item.options,
        
        # Availability and inventory
        active: item.active?,
        track_inventory: item.track_inventory?,
        in_stock: item.in_stock?,
        out_of_stock: item.out_of_stock?,
        low_stock: item.low_stock?,
        stock_status: item.stock_status,
        stock_quantity: item.track_inventory? ? item.stock_quantity : nil,
        available_quantity: item.track_inventory? ? item.available_quantity : nil,
        low_stock_threshold: item.low_stock_threshold,
        last_restocked_at: item.last_restocked_at,
        
        # Option-level inventory fields
        uses_option_level_inventory: item.uses_option_level_inventory?,
        effective_available_quantity: item.effective_available_quantity,
        
        # All images
        images: item.item_images.by_position.map do |image|
          {
            id: image.id,
            image_url: image.image_url,
            alt_text: image.alt_text,
            position: image.position,
            primary: image.primary?
          }
        end,
        primary_image_url: item.primary_image_url,
        all_image_urls: item.all_image_urls,
        
        # Statistics
        total_ordered: item.total_ordered_quantity,
        total_revenue: item.total_revenue_cents / 100.0,
        
        # Option Groups (new system)
        option_groups: item.option_groups.includes(:options).order(:position).map do |group|
          {
            id: group.id,
            name: group.name,
            min_select: group.min_select,
            max_select: group.max_select,
            required: group.required,
            position: group.position,
            enable_inventory_tracking: group.enable_inventory_tracking,
            options: group.options.order(:position).map do |option|
              {
                id: option.id,
                name: option.name,
                additional_price: option.additional_price.to_f,
                available: option.available,
                position: option.position,
                stock_quantity: option.stock_quantity,
                damaged_quantity: option.damaged_quantity,
                low_stock_threshold: option.low_stock_threshold
              }
            end
          }
        end,
        
        # Fundraiser context
        fundraiser_id: item.fundraiser_id,
        fundraiser_name: item.fundraiser.name,
        fundraiser_slug: item.fundraiser.slug,
        
        created_at: item.created_at,
        updated_at: item.updated_at
      }
    end
  end
end