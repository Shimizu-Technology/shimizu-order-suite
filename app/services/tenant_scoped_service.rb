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
  # @raise [ArgumentError] If restaurant is nil and not a global service
  def initialize(restaurant)
    @restaurant = restaurant
    # Only require restaurant if this is not a subclass that handles global operations
    unless @restaurant || self.class.global_service?
      raise ArgumentError, "Restaurant is required for tenant-scoped services"
    end
  end
  
  # Class method to indicate if this service supports global operations
  # Subclasses can override this to return true if they support global operations
  def self.global_service?
    false
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
    model_class = base_query.klass
    
    # If no restaurant context (for global operations), return unscoped query
    return base_query if @restaurant.nil?
    
    # First check if the model has a direct restaurant_id column
    if model_class.column_names.include?("restaurant_id")
      return base_query.where(restaurant_id: @restaurant.id)
    end
    
    # Check if the model has a with_restaurant_scope class method
    # This allows models to define their own tenant isolation logic
    if model_class.respond_to?(:with_restaurant_scope)
      # Check if the method accepts parameters
      method = model_class.method(:with_restaurant_scope)
      if method.arity == 1
        # Method accepts a restaurant parameter
        return model_class.with_restaurant_scope(@restaurant)
      else
        # Method doesn't accept parameters (uses ApplicationRecord.current_restaurant)
        # Temporarily set the current restaurant context for IndirectTenantScoped models
        previous_restaurant = ApplicationRecord.current_restaurant
        begin
          ApplicationRecord.current_restaurant = @restaurant
          return model_class.with_restaurant_scope
        ensure
          # Always restore the previous context
          ApplicationRecord.current_restaurant = previous_restaurant
        end
      end
    end
    
    # Get the tenant relationships configuration
    tenant_relationships = Rails.application.config.tenant_relationships rescue {}
    
    # Check if we have a predefined relationship path in the config
    if tenant_relationships.key?(model_class.name)
      relationship = tenant_relationships[model_class.name]
      
      if relationship[:direct]
        # Model has a direct restaurant_id column
        return base_query.where(relationship[:foreign_key] => @restaurant.id)
      elsif relationship[:through].is_a?(Array)
        # Model has a multi-step path to restaurant
        path = relationship[:through]
        
        # Build the joins clause
        joins_clause = path.map(&:to_sym)
        
        # The last association in the path is the one with the foreign key
        last_assoc = path.last
        
        # Join through all associations and filter by restaurant_id
        return base_query.joins(joins_clause).where(
          last_assoc.to_s.pluralize => { 
            relationship[:foreign_key] => @restaurant.id 
          }
        )
      else
        # Model has a single-step path to restaurant
        assoc = relationship[:through]
        
        # Join through the association and filter by restaurant_id
        return base_query.joins(assoc).where(
          assoc.to_s.pluralize => { 
            relationship[:foreign_key] => @restaurant.id 
          }
        )
      end
    end
    
    # Handle specific known models with indirect tenant relationships
    # Only handle models that don't already have a with_restaurant_scope method
    # and aren't defined in the tenant_relationships config
    case model_class.name
    when "Option"
      # Options belong to OptionGroups which belong to MenuItems which belong to Menus which belong to Restaurants
      return base_query.joins(option_group: { menu_item: :menu }).where(menus: { restaurant_id: @restaurant.id })
    when "OptionGroup"
      # OptionGroups belong to MenuItems which belong to Menus which belong to Restaurants
      return base_query.joins(menu_item: :menu).where(menus: { restaurant_id: @restaurant.id })
    when "Category"
      # Categories belong to Menus which belong to Restaurants
      return base_query.where(menu_id: Menu.where(restaurant_id: @restaurant.id).pluck(:id))
    when "VipCodeRecipient"
      # VipCodeRecipients belong to VipAccessCodes which belong to Restaurants
      return base_query.joins(:vip_access_code).where(vip_access_codes: { restaurant_id: @restaurant.id })
    when "StoreCredit"
      # StoreCredits belong to Users which belong to Restaurants
      return base_query.joins(:user).where(users: { restaurant_id: @restaurant.id })
    when "SeatSection"
      # SeatSections belong to Restaurants directly
      return base_query.where(restaurant_id: @restaurant.id)
    when "SeatAllocation"
      # SeatAllocations belong to Seats which belong to SeatSections which belong to Restaurants
      return base_query.joins(seat: :seat_section).where(seat_sections: { restaurant_id: @restaurant.id })
    when "Seat"
      # Seats belong to SeatSections which belong to Restaurants
      return base_query.joins(:seat_section).where(seat_sections: { restaurant_id: @restaurant.id })
    when "OrderPayment"
      # OrderPayments belong to Orders which belong to Restaurants
      return base_query.joins(:order).where(orders: { restaurant_id: @restaurant.id })
    when "OrderAcknowledgment"
      # OrderAcknowledgments belong to Orders which belong to Restaurants
      return base_query.joins(:order).where(orders: { restaurant_id: @restaurant.id })
    when "MerchandiseVariant"
      # MerchandiseVariants belong to MerchandiseItems which belong to MerchandiseCollections which belong to Restaurants
      return base_query.joins(merchandise_item: :merchandise_collection).where(merchandise_collections: { restaurant_id: @restaurant.id })
    when "MerchandiseItem"
      # MerchandiseItems belong to MerchandiseCollections which belong to Restaurants
      return base_query.joins(:merchandise_collection).where(merchandise_collections: { restaurant_id: @restaurant.id })
    when "MenuItemStockAudit"
      # MenuItemStockAudits belong to MenuItems which belong to Menus which belong to Restaurants
      return base_query.joins(menu_item: :menu).where(menus: { restaurant_id: @restaurant.id })
    when "HouseAccountTransaction"
      # HouseAccountTransactions belong to Users which belong to Restaurants
      return base_query.joins(:user).where(users: { restaurant_id: @restaurant.id })
    when "Restaurant"
      # Special case for Restaurant model - just return the current restaurant
      return base_query.where(id: @restaurant.id)
    else
      # If we don't know how to scope this model, log a warning and return the original query
      Rails.logger.warn("Model #{model_class.name} doesn't have restaurant_id column and no tenant isolation logic is defined")
      base_query
    end
  end
  
  private
  
  # Ensure a record belongs to the current restaurant
  # @param record [ActiveRecord::Base] The record to check
  # @raise [ArgumentError] If the record doesn't belong to the current restaurant
  def ensure_record_belongs_to_restaurant(record)
    # Skip validation if no restaurant context (for global operations)
    return true if @restaurant.nil?
    
    # Skip validation if record doesn't have restaurant_id
    return true unless record.respond_to?(:restaurant_id)
    
    unless record.restaurant_id == @restaurant.id
      raise ArgumentError, "Record does not belong to the current restaurant"
    end
  end
end
