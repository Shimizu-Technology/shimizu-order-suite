# app/services/merchandise_collection_service.rb
class MerchandiseCollectionService
  attr_reader :current_restaurant, :analytics
  
  def initialize(current_restaurant, analytics_service = nil)
    @current_restaurant = current_restaurant
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Get all merchandise collections with filtering
  def list_collections(params)
    begin
      if current_restaurant.present?
        collections = MerchandiseCollection.where(restaurant_id: current_restaurant.id).order(created_at: :asc)
      else
        # If no restaurant context, return empty array
        return { success: false, errors: ["Restaurant context required"], status: :unprocessable_entity }
      end
      
      { success: true, collections: collections }
    rescue => e
      { success: false, errors: ["Failed to retrieve collections: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Get a specific merchandise collection by ID
  def get_collection(id)
    begin
      collection = MerchandiseCollection.find_by(id: id, restaurant_id: current_restaurant.id)
      
      unless collection
        return { success: false, errors: ["Collection not found"], status: :not_found }
      end
      
      { success: true, collection: collection }
    rescue => e
      { success: false, errors: ["Failed to retrieve collection: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Create a new merchandise collection
  def create_collection(collection_params, current_user)
    begin
      # Ensure the collection belongs to the current restaurant
      collection_params_with_restaurant = collection_params.merge(restaurant_id: current_restaurant.id)
      
      collection = MerchandiseCollection.new(collection_params_with_restaurant)
      
      if collection.save
        # Track collection creation
        analytics.track("merchandise_collection.created", { 
          collection_id: collection.id,
          restaurant_id: current_restaurant.id,
          user_id: current_user&.id
        })
        
        { success: true, collection: collection, status: :created }
      else
        { success: false, errors: collection.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to create collection: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Update an existing merchandise collection
  def update_collection(id, collection_params, current_user)
    begin
      collection = MerchandiseCollection.find_by(id: id, restaurant_id: current_restaurant.id)
      
      unless collection
        return { success: false, errors: ["Collection not found"], status: :not_found }
      end
      
      if collection.update(collection_params)
        # Track collection update
        analytics.track("merchandise_collection.updated", { 
          collection_id: collection.id,
          restaurant_id: current_restaurant.id,
          user_id: current_user&.id
        })
        
        { success: true, collection: collection }
      else
        { success: false, errors: collection.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to update collection: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Delete a merchandise collection
  def delete_collection(id, current_user)
    begin
      collection = MerchandiseCollection.find_by(id: id, restaurant_id: current_restaurant.id)
      
      unless collection
        return { success: false, errors: ["Collection not found"], status: :not_found }
      end
      
      # Check if this is the active collection
      if current_restaurant.current_merchandise_collection_id == collection.id
        return { success: false, errors: ["Cannot delete the active collection. Please set another collection as active first."], status: :unprocessable_entity }
      end
      
      if collection.destroy
        # Track collection deletion
        analytics.track("merchandise_collection.deleted", { 
          collection_id: id,
          restaurant_id: current_restaurant.id,
          user_id: current_user&.id
        })
        
        { success: true, message: "Collection deleted successfully" }
      else
        { success: false, errors: ["Failed to delete collection"], status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to delete collection: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Set a collection as active
  def set_active_collection(id, current_user)
    begin
      # Only admin users can set active collections
      unless current_user&.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      collection = MerchandiseCollection.find_by(id: id, restaurant_id: current_restaurant.id)
      
      unless collection
        return { success: false, errors: ["Collection not found"], status: :not_found }
      end
      
      # Start a transaction to ensure all updates happen together
      ActiveRecord::Base.transaction do
        # Set all collections for this restaurant to inactive
        current_restaurant.merchandise_collections.update_all(active: false)
        
        # Set the selected collection to active
        collection.update!(active: true)
        
        # Update the restaurant's current_merchandise_collection_id
        current_restaurant.update!(current_merchandise_collection_id: collection.id)
      end
      
      # Track setting active collection
      analytics.track("merchandise_collection.set_active", { 
        collection_id: collection.id,
        restaurant_id: current_restaurant.id,
        user_id: current_user.id
      })
      
      { 
        success: true, 
        message: "Collection set as active successfully",
        current_merchandise_collection_id: current_restaurant.current_merchandise_collection_id
      }
    rescue => e
      { success: false, errors: ["Failed to set active collection: #{e.message}"], status: :internal_server_error }
    end
  end
end
