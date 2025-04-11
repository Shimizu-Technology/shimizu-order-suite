# app/models/concerns/tenant_scoped.rb
module TenantScoped
  extend ActiveSupport::Concern
  
  included do
    # Apply default scope for tenant isolation if the model has a restaurant_id column
    default_scope { with_restaurant_scope }
    
    # Add validation for restaurant_id presence
    validates :restaurant_id, presence: true, if: -> { self.class.column_names.include?("restaurant_id") }
    
    # Add belongs_to association if not already defined
    unless reflect_on_association(:restaurant)
      belongs_to :restaurant, optional: false
    end
  end
  
  class_methods do
    # Method to scope by current restaurant if applicable
    def with_restaurant_scope
      if ApplicationRecord.current_restaurant && column_names.include?("restaurant_id")
        where(restaurant_id: ApplicationRecord.current_restaurant.id)
      else
        all
      end
    end
    
    # Method to explicitly scope a query to a specific restaurant
    def for_restaurant(restaurant)
      if column_names.include?("restaurant_id")
        where(restaurant_id: restaurant.is_a?(Restaurant) ? restaurant.id : restaurant)
      else
        all
      end
    end
    
    # Method to bypass tenant scoping for a specific query
    def unscoped_query
      unscoped
    end
  end
end
