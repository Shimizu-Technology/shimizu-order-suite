# app/services/tenant_scoped_service.rb
#
# The TenantScopedService class provides a base class for all service objects
# that need to enforce tenant isolation. It ensures that all data access
# is properly scoped to the current restaurant.
#
# This class should be used as the parent class for all service objects
# that access restaurant-specific data.
#
class TenantScopedService
  attr_reader :restaurant
  
  # Initialize with a restaurant context
  # @param restaurant [Restaurant] The restaurant context for this service
  # @raise [ArgumentError] If restaurant is nil
  def initialize(restaurant)
    @restaurant = restaurant
    raise ArgumentError, "Restaurant is required for tenant-scoped services" unless @restaurant
  end
  
  # Find records of the given model class, automatically scoped to the current restaurant
  # @param model_class [Class] The ActiveRecord model class to query
  # @param filters [Hash] Additional filters to apply to the query
  # @return [ActiveRecord::Relation] A relation scoped to the current restaurant
  def find_records(model_class, filters = {})
    scope_query(model_class).where(filters)
  end
  
  # Find a single record by ID, ensuring it belongs to the current restaurant
  # @param model_class [Class] The ActiveRecord model class to query
  # @param id [Integer] The ID of the record to find
  # @return [ActiveRecord::Base, nil] The found record or nil
  def find_record_by_id(model_class, id)
    scope_query(model_class).find_by(id: id)
  end
  
  # Create a new record with the current restaurant context
  # @param model_class [Class] The ActiveRecord model class to create
  # @param attributes [Hash] Attributes for the new record
  # @return [ActiveRecord::Base] The created record
  def create_record(model_class, attributes = {})
    model_class.create(attributes.merge(restaurant_id: @restaurant.id))
  end
  
  # Update a record, ensuring it belongs to the current restaurant
  # @param record [ActiveRecord::Base] The record to update
  # @param attributes [Hash] New attributes for the record
  # @return [Boolean] Whether the update was successful
  # @raise [ArgumentError] If the record doesn't belong to the current restaurant
  def update_record(record, attributes = {})
    ensure_record_belongs_to_restaurant(record)
    record.update(attributes)
  end
  
  # Delete a record, ensuring it belongs to the current restaurant
  # @param record [ActiveRecord::Base] The record to delete
  # @return [Boolean] Whether the deletion was successful
  # @raise [ArgumentError] If the record doesn't belong to the current restaurant
  def delete_record(record)
    ensure_record_belongs_to_restaurant(record)
    record.destroy
  end
  
  # Scope any query to the current restaurant
  # @param query [ActiveRecord::Relation, Class] The query or model class to scope
  # @return [ActiveRecord::Relation] A relation scoped to the current restaurant
  def scope_query(query)
    base_query = query.is_a?(Class) ? query.all : query
    
    if base_query.klass.column_names.include?("restaurant_id")
      base_query.where(restaurant_id: @restaurant.id)
    else
      # If the model doesn't have a restaurant_id column, return the original query
      # This should be rare and carefully considered
      Rails.logger.warn("Model #{base_query.klass.name} doesn't have restaurant_id column, tenant isolation may be compromised")
      base_query
    end
  end
  
  private
  
  # Ensure a record belongs to the current restaurant
  # @param record [ActiveRecord::Base] The record to check
  # @raise [ArgumentError] If the record doesn't belong to the current restaurant
  def ensure_record_belongs_to_restaurant(record)
    return true unless record.respond_to?(:restaurant_id)
    
    unless record.restaurant_id == @restaurant.id
      raise ArgumentError, "Record does not belong to the current restaurant"
    end
  end
end
