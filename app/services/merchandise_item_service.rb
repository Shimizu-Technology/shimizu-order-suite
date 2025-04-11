# app/services/merchandise_item_service.rb
class MerchandiseItemService < TenantScopedService
  attr_reader :analytics
  
  def initialize(restaurant, analytics_service = nil)
    super(restaurant)
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Get all merchandise items with filtering
  def list_items(params, current_user)
    begin
      # If admin AND params[:show_all] => show all. Otherwise only available.
      if is_admin?(current_user) && params[:show_all].present?
        base_scope = MerchandiseItem.joins(:merchandise_collection)
                                   .where(merchandise_collections: { restaurant_id: restaurant.id })
      else
        base_scope = MerchandiseItem.joins(:merchandise_collection)
                                   .where(merchandise_collections: { restaurant_id: restaurant.id })
                                   .where(available: true)
      end
      
      # Filter by collection_id if provided
      if params[:collection_id].present?
        # Verify the collection belongs to the current restaurant
        collection = MerchandiseCollection.find_by(id: params[:collection_id], restaurant_id: restaurant.id)
        if collection
          base_scope = base_scope.where(merchandise_collection_id: collection.id)
        else
          return { success: false, errors: ["Collection not found"], status: :not_found }
        end
      # Otherwise, filter by the restaurant's current collection if available
      elsif restaurant&.current_merchandise_collection_id.present?
        base_scope = base_scope.where(merchandise_collection_id: restaurant.current_merchandise_collection_id)
      end
      
      # Sort by name
      base_scope = base_scope.order(:name)
      
      items = base_scope.includes(:merchandise_variants)
      
      # Include collection name for each item when returning all items
      if params[:include_collection_names].present?
        items_with_collection = items.map do |item|
          item_json = item.as_json(include_variants: true)
          item_json["collection_name"] = item.merchandise_collection&.name
          item_json
        end
        
        { success: true, items: items_with_collection }
      else
        { success: true, items: items.as_json(include_variants: true) }
      end
    rescue => e
      { success: false, errors: ["Failed to retrieve items: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Get a specific merchandise item by ID
  def get_item(id)
    begin
      # Join with merchandise_collections to ensure tenant isolation
      item = MerchandiseItem.joins(:merchandise_collection)
                           .where(merchandise_collections: { restaurant_id: restaurant.id })
                           .includes(:merchandise_variants)
                           .find_by(id: id)
      
      unless item
        return { success: false, errors: ["Item not found"], status: :not_found }
      end
      
      { success: true, item: item.as_json(include_variants: true) }
    rescue => e
      { success: false, errors: ["Failed to retrieve item: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Create a new merchandise item
  def create_item(item_params, current_user)
    begin
      # Only admin users can create items
      unless is_admin?(current_user)
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      # Verify the collection belongs to the current restaurant
      collection = MerchandiseCollection.find_by(id: item_params[:merchandise_collection_id], restaurant_id: restaurant.id)
      unless collection
        return { success: false, errors: ["Collection not found or does not belong to this restaurant"], status: :unprocessable_entity }
      end
      
      merchandise_item = MerchandiseItem.new(item_params.except(:image, :second_image))
      
      if merchandise_item.save
        # Handle image upload if present
        file = item_params[:image]
        if file.present? && file.respond_to?(:original_filename)
          ext = File.extname(file.original_filename)
          new_filename = "merchandise_item_#{merchandise_item.id}_#{Time.now.to_i}#{ext}"
          public_url = S3Uploader.upload(file, new_filename)
          merchandise_item.update!(image_url: public_url)
        end
        
        # Handle second image upload if present
        second_file = item_params[:second_image]
        if second_file.present? && second_file.respond_to?(:original_filename)
          ext = File.extname(second_file.original_filename)
          new_filename = "merchandise_item_second_#{merchandise_item.id}_#{Time.now.to_i}#{ext}"
          public_url = S3Uploader.upload(second_file, new_filename)
          merchandise_item.update!(second_image_url: public_url)
        end
        
        # Track item creation
        analytics.track("merchandise_item.created", { 
          item_id: merchandise_item.id,
          collection_id: merchandise_item.merchandise_collection_id,
          restaurant_id: restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, item: merchandise_item, status: :created }
      else
        { success: false, errors: merchandise_item.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to create item: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Update an existing merchandise item
  def update_item(id, item_params, current_user)
    begin
      # Only admin users can update items
      unless is_admin?(current_user)
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      # Join with merchandise_collections to ensure tenant isolation
      merchandise_item = MerchandiseItem.joins(:merchandise_collection)
                                       .where(merchandise_collections: { restaurant_id: restaurant.id })
                                       .find_by(id: id)
      
      unless merchandise_item
        return { success: false, errors: ["Item not found"], status: :not_found }
      end
      
      # If changing the collection, verify the new collection belongs to the current restaurant
      if item_params[:merchandise_collection_id].present? && 
         item_params[:merchandise_collection_id].to_i != merchandise_item.merchandise_collection_id
        collection = MerchandiseCollection.find_by(id: item_params[:merchandise_collection_id], restaurant_id: restaurant.id)
        unless collection
          return { success: false, errors: ["Collection not found or does not belong to this restaurant"], status: :unprocessable_entity }
        end
      end
      
      if merchandise_item.update(item_params.except(:image, :second_image))
        # Handle image if present
        file = item_params[:image]
        if file.present? && file.respond_to?(:original_filename)
          ext = File.extname(file.original_filename)
          new_filename = "merchandise_item_#{merchandise_item.id}_#{Time.now.to_i}#{ext}"
          public_url = S3Uploader.upload(file, new_filename)
          merchandise_item.update!(image_url: public_url)
        end
        
        # Handle second image if present
        second_file = item_params[:second_image]
        if second_file.present? && second_file.respond_to?(:original_filename)
          ext = File.extname(second_file.original_filename)
          new_filename = "merchandise_item_second_#{merchandise_item.id}_#{Time.now.to_i}#{ext}"
          public_url = S3Uploader.upload(second_file, new_filename)
          merchandise_item.update!(second_image_url: public_url)
        end
        
        # Track item update
        analytics.track("merchandise_item.updated", { 
          item_id: merchandise_item.id,
          collection_id: merchandise_item.merchandise_collection_id,
          restaurant_id: restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, item: merchandise_item }
      else
        { success: false, errors: merchandise_item.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to update item: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Delete a merchandise item
  def delete_item(id, current_user)
    begin
      # Only admin users can delete items
      unless is_admin?(current_user)
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      # Join with merchandise_collections to ensure tenant isolation
      merchandise_item = MerchandiseItem.joins(:merchandise_collection)
                                       .where(merchandise_collections: { restaurant_id: restaurant.id })
                                       .find_by(id: id)
      
      unless merchandise_item
        return { success: false, errors: ["Item not found"], status: :not_found }
      end
      
      if merchandise_item.destroy
        # Track item deletion
        analytics.track("merchandise_item.deleted", { 
          item_id: id,
          collection_id: merchandise_item.merchandise_collection_id,
          restaurant_id: restaurant.id,
          user_id: current_user.id
        })
        
        { success: true, message: "Item deleted successfully" }
      else
        { success: false, errors: ["Failed to delete item"], status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to delete item: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Upload an image for a merchandise item
  def upload_image(id, file, current_user, is_second_image = false)
    begin
      # Only admin users can upload images
      unless is_admin?(current_user)
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      # Join with merchandise_collections to ensure tenant isolation
      merchandise_item = MerchandiseItem.joins(:merchandise_collection)
                                       .where(merchandise_collections: { restaurant_id: restaurant.id })
                                       .find_by(id: id)
      
      unless merchandise_item
        return { success: false, errors: ["Item not found"], status: :not_found }
      end
      
      unless file
        return { success: false, errors: ["No image file uploaded"], status: :unprocessable_entity }
      end
      
      ext = File.extname(file.original_filename)
      
      if is_second_image
        new_filename = "merchandise_item_second_#{merchandise_item.id}_#{Time.now.to_i}#{ext}"
        public_url = S3Uploader.upload(file, new_filename)
        merchandise_item.update!(second_image_url: public_url)
        
        # Track second image upload
        analytics.track("merchandise_item.second_image_uploaded", { 
          item_id: merchandise_item.id,
          restaurant_id: restaurant.id,
          user_id: current_user.id
        })
      else
        new_filename = "merchandise_item_#{merchandise_item.id}_#{Time.now.to_i}#{ext}"
        public_url = S3Uploader.upload(file, new_filename)
        merchandise_item.update!(image_url: public_url)
        
        # Track image upload
        analytics.track("merchandise_item.image_uploaded", { 
          item_id: merchandise_item.id,
          restaurant_id: restaurant.id,
          user_id: current_user.id
        })
      end
      
      { success: true, item: merchandise_item }
    rescue => e
      { success: false, errors: ["Failed to upload image: #{e.message}"], status: :internal_server_error }
    end
  end
  
  private
  
  def is_admin?(user)
    user && user.role.in?(%w[admin super_admin])
  end
end
