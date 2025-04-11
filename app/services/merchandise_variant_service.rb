# app/services/merchandise_variant_service.rb
class MerchandiseVariantService
  attr_reader :current_restaurant, :analytics
  
  def initialize(current_restaurant, analytics_service = nil)
    @current_restaurant = current_restaurant
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Get all merchandise variants with filtering
  def list_variants(params)
    begin
      # Join with merchandise_items and merchandise_collections to ensure tenant isolation
      variants = MerchandiseVariant.joins(merchandise_item: :merchandise_collection)
                                  .where(merchandise_collections: { restaurant_id: current_restaurant.id })
                                  .includes(:merchandise_item)
      
      # Filter by merchandise_item_id if provided
      if params[:merchandise_item_id].present?
        # Verify the item belongs to the current restaurant
        item = MerchandiseItem.joins(:merchandise_collection)
                             .where(merchandise_collections: { restaurant_id: current_restaurant.id })
                             .find_by(id: params[:merchandise_item_id])
        
        if item
          variants = variants.where(merchandise_item_id: item.id)
        else
          return { success: false, errors: ["Item not found"], status: :not_found }
        end
      end
      
      # Apply additional filters
      if params[:color].present?
        variants = variants.where(color: params[:color])
      end
      
      if params[:size].present?
        variants = variants.where(size: params[:size])
      end
      
      # Filter by stock status
      if params[:stock_status].present?
        case params[:stock_status]
        when "in_stock"
          variants = variants.where("merchandise_variants.stock_quantity > 0")
        when "out_of_stock"
          variants = variants.where(stock_quantity: 0)
        when "low_stock"
          variants = variants.where("merchandise_variants.stock_quantity > 0 AND merchandise_variants.stock_quantity <= COALESCE(merchandise_variants.low_stock_threshold, 5)")
        end
      end
      
      { success: true, variants: variants }
    rescue => e
      { success: false, errors: ["Failed to retrieve variants: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Get a specific merchandise variant by ID
  def get_variant(id)
    begin
      # Join with merchandise_items and merchandise_collections to ensure tenant isolation
      variant = MerchandiseVariant.joins(merchandise_item: :merchandise_collection)
                                 .where(merchandise_collections: { restaurant_id: current_restaurant.id })
                                 .find_by(id: id)
      
      unless variant
        return { success: false, errors: ["Variant not found"], status: :not_found }
      end
      
      { success: true, variant: variant }
    rescue => e
      { success: false, errors: ["Failed to retrieve variant: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Create a new merchandise variant
  def create_variant(variant_params, current_user)
    begin
      # Only admin users can create variants
      unless is_admin?(current_user)
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      # Verify the item belongs to the current restaurant
      item = MerchandiseItem.joins(:merchandise_collection)
                           .where(merchandise_collections: { restaurant_id: current_restaurant.id })
                           .find_by(id: variant_params[:merchandise_item_id])
      
      unless item
        return { success: false, errors: ["Item not found or does not belong to this restaurant"], status: :unprocessable_entity }
      end
      
      variant = MerchandiseVariant.new(variant_params)
      
      if variant.save
        # Track variant creation
        analytics.track("merchandise_variant.created", { 
          variant_id: variant.id,
          item_id: variant.merchandise_item_id,
          restaurant_id: current_restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, variant: variant, status: :created }
      else
        { success: false, errors: variant.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to create variant: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Update an existing merchandise variant
  def update_variant(id, variant_params, current_user)
    begin
      # Only admin users can update variants
      unless is_admin?(current_user)
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      # Join with merchandise_items and merchandise_collections to ensure tenant isolation
      variant = MerchandiseVariant.joins(merchandise_item: :merchandise_collection)
                                 .where(merchandise_collections: { restaurant_id: current_restaurant.id })
                                 .find_by(id: id)
      
      unless variant
        return { success: false, errors: ["Variant not found"], status: :not_found }
      end
      
      # If changing the item, verify the new item belongs to the current restaurant
      if variant_params[:merchandise_item_id].present? && 
         variant_params[:merchandise_item_id].to_i != variant.merchandise_item_id
        item = MerchandiseItem.joins(:merchandise_collection)
                             .where(merchandise_collections: { restaurant_id: current_restaurant.id })
                             .find_by(id: variant_params[:merchandise_item_id])
        
        unless item
          return { success: false, errors: ["Item not found or does not belong to this restaurant"], status: :unprocessable_entity }
        end
      end
      
      if variant.update(variant_params)
        # Track variant update
        analytics.track("merchandise_variant.updated", { 
          variant_id: variant.id,
          item_id: variant.merchandise_item_id,
          restaurant_id: current_restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, variant: variant }
      else
        { success: false, errors: variant.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to update variant: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Delete a merchandise variant
  def delete_variant(id, current_user)
    begin
      # Only admin users can delete variants
      unless is_admin?(current_user)
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      # Join with merchandise_items and merchandise_collections to ensure tenant isolation
      variant = MerchandiseVariant.joins(merchandise_item: :merchandise_collection)
                                 .where(merchandise_collections: { restaurant_id: current_restaurant.id })
                                 .find_by(id: id)
      
      unless variant
        return { success: false, errors: ["Variant not found"], status: :not_found }
      end
      
      if variant.destroy
        # Track variant deletion
        analytics.track("merchandise_variant.deleted", { 
          variant_id: id,
          item_id: variant.merchandise_item_id,
          restaurant_id: current_restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, message: "Variant deleted successfully" }
      else
        { success: false, errors: ["Failed to delete variant"], status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to delete variant: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Batch create variants for a merchandise item
  def batch_create_variants(merchandise_item_id, variants_params, current_user)
    begin
      # Only admin users can create variants
      unless is_admin?(current_user)
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      # Validate parameters
      unless merchandise_item_id.present? && variants_params.present? && variants_params.is_a?(Array)
        return { success: false, errors: ["Invalid parameters"], status: :unprocessable_entity }
      end
      
      # Verify the item belongs to the current restaurant
      item = MerchandiseItem.joins(:merchandise_collection)
                           .where(merchandise_collections: { restaurant_id: current_restaurant.id })
                           .find_by(id: merchandise_item_id)
      
      unless item
        return { success: false, errors: ["Item not found or does not belong to this restaurant"], status: :not_found }
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
            stock_quantity: variant_param[:stock_quantity] || 0,
            sku: variant_param[:sku],
            low_stock_threshold: variant_param[:low_stock_threshold]
          )
          
          if variant.save
            created_variants << variant
            
            # Track variant creation
            analytics.track("merchandise_variant.batch_created", { 
              variant_id: variant.id,
              item_id: variant.merchandise_item_id,
              restaurant_id: current_restaurant.id,
              user_id: current_user.id
            })
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
        { 
          success: true, 
          message: "All variants created successfully",
          variants: created_variants,
          status: :created
        }
      else
        { 
          success: false, 
          errors: ["Failed to create variants"],
          failed_variants: failed_variants,
          status: :unprocessable_entity
        }
      end
    rescue => e
      { success: false, errors: ["Failed to batch create variants: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Add stock to a variant
  def add_stock(id, quantity, reason, current_user)
    begin
      # Only admin users can add stock
      unless is_admin?(current_user)
        return { success: false, errors: ["Forbidden - Admin access required"], status: :forbidden }
      end
      
      # Validate quantity
      if quantity <= 0
        return { success: false, errors: ["Quantity must be greater than 0"], status: :unprocessable_entity }
      end
      
      # Join with merchandise_items and merchandise_collections to ensure tenant isolation
      variant = MerchandiseVariant.joins(merchandise_item: :merchandise_collection)
                                 .where(merchandise_collections: { restaurant_id: current_restaurant.id })
                                 .find_by(id: id)
      
      unless variant
        return { success: false, errors: ["Variant not found"], status: :not_found }
      end
      
      reason ||= "Manual addition"
      new_quantity = variant.add_stock!(quantity, reason)
      
      # Track stock addition
      analytics.track("merchandise_variant.stock_added", { 
        variant_id: variant.id,
        item_id: variant.merchandise_item_id,
        quantity: quantity,
        new_quantity: new_quantity,
        restaurant_id: current_restaurant.id,
        user_id: current_user.id,
        reason: reason
      })
      
      { 
        success: true, 
        message: "Successfully added #{quantity} to stock",
        new_quantity: new_quantity,
        variant: variant
      }
    rescue => e
      { success: false, errors: ["Failed to add stock: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Reduce stock from a variant
  def reduce_stock(id, quantity, reason, allow_negative, current_user)
    begin
      # Only admin users can reduce stock
      unless is_admin?(current_user)
        return { success: false, errors: ["Forbidden - Admin access required"], status: :forbidden }
      end
      
      # Validate quantity
      if quantity <= 0
        return { success: false, errors: ["Quantity must be greater than 0"], status: :unprocessable_entity }
      end
      
      # Join with merchandise_items and merchandise_collections to ensure tenant isolation
      variant = MerchandiseVariant.joins(merchandise_item: :merchandise_collection)
                                 .where(merchandise_collections: { restaurant_id: current_restaurant.id })
                                 .find_by(id: id)
      
      unless variant
        return { success: false, errors: ["Variant not found"], status: :not_found }
      end
      
      reason ||= "Manual reduction"
      
      begin
        new_quantity = variant.reduce_stock!(quantity, allow_negative, reason)
        
        # Track stock reduction
        analytics.track("merchandise_variant.stock_reduced", { 
          variant_id: variant.id,
          item_id: variant.merchandise_item_id,
          quantity: quantity,
          new_quantity: new_quantity,
          restaurant_id: current_restaurant.id,
          user_id: current_user.id,
          reason: reason,
          allow_negative: allow_negative
        })
        
        { 
          success: true, 
          message: "Successfully reduced stock by #{quantity}",
          new_quantity: new_quantity,
          variant: variant
        }
      rescue StandardError => e
        { success: false, errors: [e.message], status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to reduce stock: #{e.message}"], status: :internal_server_error }
    end
  end
  
  private
  
  def is_admin?(user)
    user && user.role.in?(%w[admin super_admin])
  end
end
