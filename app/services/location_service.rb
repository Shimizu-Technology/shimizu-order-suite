# app/services/location_service.rb
#
# The LocationService class provides methods for managing restaurant locations
# with proper tenant isolation.
#
class LocationService < TenantScopedService
  # Get all locations for the current restaurant
  # @param include_inactive [Boolean] Whether to include inactive locations
  # @return [ActiveRecord::Relation] A relation of locations
  def all_locations(include_inactive: false)
    locations = find_records(Location)
    locations = locations.where(is_active: true) unless include_inactive
    locations
  end

  # Get the default location for the current restaurant
  # @return [Location, nil] The default location or nil if none exists
  def default_location
    find_records(Location).find_by(is_default: true)
  end

  # Find a location by ID, ensuring it belongs to the current restaurant
  # @param id [Integer] The ID of the location to find
  # @return [Location, nil] The found location or nil
  def find_location(id)
    find_record_by_id(Location, id)
  end

  # Create a new location for the current restaurant
  # @param attributes [Hash] Attributes for the new location
  # @return [Location] The created location
  def create_location(attributes)
    # If this is the first location, make it the default
    attributes[:is_default] = true if find_records(Location).count == 0
    
    location = create_record(Location, attributes)
    
    # If this is marked as default, ensure no other locations are default
    if location.persisted? && location.is_default?
      Location.transaction do
        find_records(Location)
          .where.not(id: location.id)
          .where(is_default: true)
          .update_all(is_default: false)
      end
    end
    
    location
  end

  # Update a location, ensuring it belongs to the current restaurant
  # @param id [Integer] The ID of the location to update
  # @param attributes [Hash] New attributes for the location
  # @return [Location, nil] The updated location or nil if not found
  def update_location(id, attributes)
    location = find_location(id)
    return nil unless location
    
    # Handle default location logic
    was_default = location.is_default?
    will_be_default = attributes.key?(:is_default) ? attributes[:is_default] : was_default
    
    # If this location is being set as default, ensure no other locations are default
    if will_be_default && !was_default
      Location.transaction do
        update_record(location, attributes)
        
        find_records(Location)
          .where.not(id: location.id)
          .where(is_default: true)
          .update_all(is_default: false)
      end
    else
      # Normal update
      update_record(location, attributes)
    end
    
    location
  end

  # Set a location as the default for the current restaurant
  # @param id [Integer] The ID of the location to set as default
  # @return [Location, nil] The updated location or nil if not found
  def set_default_location(id)
    location = find_location(id)
    return nil unless location
    
    location.make_default!
    location
  end

  # Delete a location, ensuring it belongs to the current restaurant
  # @param id [Integer] The ID of the location to delete
  # @return [Boolean] Whether the deletion was successful
  def delete_location(id)
    location = find_location(id)
    return false unless location
    
    # Don't allow deletion of the default location if there are other locations
    if location.is_default? && find_records(Location).count > 1
      return false
    end
    
    # Don't allow deletion if there are orders associated with this location
    if location.orders.exists?
      return false
    end
    
    delete_record(location)
  end
  
  # Check if the restaurant has multiple active locations
  # @return [Boolean] Whether the restaurant has multiple active locations
  def has_multiple_active_locations?
    find_records(Location).where(is_active: true).count > 1
  end
end
