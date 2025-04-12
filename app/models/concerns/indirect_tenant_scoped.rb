# app/models/concerns/indirect_tenant_scoped.rb
#
# This concern provides tenant isolation for models that don't have a direct
# restaurant_id column but instead have an indirect relationship to a restaurant
# through associations.
#
# Usage:
# class MenuItem < ApplicationRecord
#   include IndirectTenantScoped
#   
#   # Define the path to restaurant (required)
#   tenant_path through: :menu, foreign_key: 'restaurant_id'
#   
#   # Or for multi-step paths:
#   # tenant_path through: [:option_group, :menu_item, :menu], foreign_key: 'restaurant_id'
# end
#
module IndirectTenantScoped
  extend ActiveSupport::Concern

  included do
    # Apply default scope for tenant isolation
    default_scope { with_restaurant_scope }
    
    # Add class-level tracking of tenant path
    class_attribute :tenant_path_config, instance_writer: false
  end
  
  class_methods do
    # Define the path to the restaurant for this model
    def tenant_path(options)
      self.tenant_path_config = options
      
      # If the path is an array, we need to define the associations
      if options[:through].is_a?(Array)
        # Get the first association in the path
        first_assoc = options[:through].first
        
        # Define has_one :restaurant association through the path
        has_one :restaurant, through: first_assoc
      else
        # Define has_one :restaurant association through the single association
        has_one :restaurant, through: options[:through]
      end
    end
    
    # Method to scope by current restaurant
    def with_restaurant_scope
      return all unless ApplicationRecord.current_restaurant
      return all unless tenant_path_config.present?
      
      if tenant_path_config[:through].is_a?(Array)
        # Multi-step path
        path = tenant_path_config[:through]
        
        # Build the joins clause
        joins_clause = path.map(&:to_sym)
        
        # The last association in the path is the one with the foreign key
        last_assoc = path.last
        
        # Join through all associations and filter by restaurant_id
        joins(joins_clause).where(
          last_assoc.to_s.pluralize => { 
            tenant_path_config[:foreign_key] => ApplicationRecord.current_restaurant.id 
          }
        )
      else
        # Single-step path
        assoc = tenant_path_config[:through]
        
        # Join through the association and filter by restaurant_id
        joins(assoc).where(
          assoc.to_s.pluralize => { 
            tenant_path_config[:foreign_key] => ApplicationRecord.current_restaurant.id 
          }
        )
      end
    end
    
    # Method to explicitly scope a query to a specific restaurant
    def for_restaurant(restaurant)
      restaurant_id = restaurant.is_a?(Restaurant) ? restaurant.id : restaurant
      
      if tenant_path_config[:through].is_a?(Array)
        # Multi-step path
        path = tenant_path_config[:through]
        
        # Build the joins clause
        joins_clause = path.map(&:to_sym)
        
        # The last association in the path is the one with the foreign key
        last_assoc = path.last
        
        # Join through all associations and filter by restaurant_id
        joins(joins_clause).where(
          last_assoc.to_s.pluralize => { 
            tenant_path_config[:foreign_key] => restaurant_id 
          }
        )
      else
        # Single-step path
        assoc = tenant_path_config[:through]
        
        # Join through the association and filter by restaurant_id
        joins(assoc).where(
          assoc.to_s.pluralize => { 
            tenant_path_config[:foreign_key] => restaurant_id 
          }
        )
      end
    end
    
    # Method to bypass tenant scoping for a specific query
    def unscoped_query
      unscoped
    end
  end
end
