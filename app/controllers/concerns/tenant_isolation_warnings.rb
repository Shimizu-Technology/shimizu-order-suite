# app/controllers/concerns/tenant_isolation_warnings.rb
#
# This module provides methods for warning about models that may not have
# proper tenant isolation. It's used by the TenantIsolation concern.
#
module TenantIsolationWarnings
  # Check for models that might not have proper tenant isolation
  # This helps identify potential tenant isolation issues during development
  def self.check_models(restaurant)
    # Skip checks if no restaurant is provided
    return unless restaurant.present?
    
    # In development and test environments, log to debug level instead of warn
    log_level = Rails.env.development? || Rails.env.test? ? :debug : :warn
    
    # Get the list of models with indirect tenant relationships
    indirect_tenant_models = Rails.application.config.indirect_tenant_models rescue []
    
    # Get the tenant relationships configuration
    tenant_relationships = Rails.application.config.tenant_relationships rescue {}
    
    # Check each model for proper tenant isolation
    ApplicationRecord.descendants.each do |model|
      # Skip models we know have indirect tenant relationships
      next if indirect_tenant_models.include?(model.name)
      
      # Skip models that don't have a table yet (during migrations)
      next unless model.table_exists? rescue false
      
      # Skip STI child classes (they use the parent's table)
      next if model.superclass != ApplicationRecord && model.superclass < ApplicationRecord
      
      # Check if the model has a with_restaurant_scope method
      has_scope_method = model.respond_to?(:with_restaurant_scope)
      
      # Check if the model has a restaurant association
      has_restaurant_association = model.reflect_on_association(:restaurant).present?
      
      # Check if the model has a restaurant_id column
      has_restaurant_id = model.column_names.include?("restaurant_id")
      
      # If the model doesn't have a restaurant_id column, check for indirect relationships
      unless has_restaurant_id
        # Check for associations that might lead to a restaurant
        indirect_path_to_restaurant = false
        
        # Check for has_one/belongs_to :restaurant, through: association
        model.reflect_on_all_associations.each do |assoc|
          if assoc.options[:through] && 
             (assoc.name == :restaurant || 
              (assoc.klass.respond_to?(:reflect_on_association) && 
               assoc.klass.reflect_on_association(:restaurant)))
            indirect_path_to_restaurant = true
            break
          end
        end
        
        # If we don't have any tenant isolation mechanism, log a warning
        unless has_scope_method || has_restaurant_association || indirect_path_to_restaurant
          Rails.logger.send(log_level, "Model #{model.name} doesn't have restaurant_id column or indirect path to restaurant, tenant isolation may be compromised")
          
          # Suggest a fix based on the model's associations and tenant relationships config
          # Only in development or test environments
          suggest_tenant_isolation_fix(model, tenant_relationships) if Rails.env.development? || Rails.env.test?
        end
      end
    end
  end
  
  # Suggest a fix for a model without proper tenant isolation
  def self.suggest_tenant_isolation_fix(model, tenant_relationships)
    # First check if we have a predefined relationship path in the config
    if tenant_relationships.key?(model.name)
      relationship = tenant_relationships[model.name]
      
      if relationship[:direct]
        # Model should have a direct restaurant_id column
        Rails.logger.info("TENANT ISOLATION FIX: For #{model.name}, add a #{relationship[:foreign_key]} column and include TenantScoped")
        Rails.logger.info("TENANT ISOLATION FIX: Run: rails g migration Add#{relationship[:foreign_key].camelize}To#{model.name.pluralize} #{relationship[:foreign_key]}:references")
      elsif relationship[:through].is_a?(Array)
        # Model has a multi-step path to restaurant
        path_description = relationship[:through].map(&:to_s).join(' -> ')
        Rails.logger.info("TENANT ISOLATION FIX: For #{model.name}, add: has_one :restaurant, through: :#{relationship[:through].first}")
        Rails.logger.info("TENANT ISOLATION FIX: Path to restaurant: #{path_description}")
        
        # Generate with_restaurant_scope method
        generate_scope_method(model, relationship[:through])
      else
        # Model has a single-step path to restaurant
        Rails.logger.info("TENANT ISOLATION FIX: For #{model.name}, add: has_one :restaurant, through: :#{relationship[:through]}")
        
        # Generate with_restaurant_scope method
        generate_scope_method(model, [relationship[:through]])
      end
      
      return
    end
    
    # If no predefined relationship, look for potential paths to a restaurant through associations
    potential_paths = []
    
    model.reflect_on_all_associations.each do |assoc|
      # Skip polymorphic associations
      next if assoc.options[:polymorphic]
      
      # Check if this association's class has a restaurant_id or restaurant association
      if assoc.klass.column_names.include?("restaurant_id") || 
         assoc.klass.reflect_on_association(:restaurant).present?
        potential_paths << assoc.name
      end
    end
    
    if potential_paths.any?
      path = potential_paths.first
      Rails.logger.info("TENANT ISOLATION FIX: For #{model.name}, consider adding: has_one :restaurant, through: :#{path}")
      
      # Generate with_restaurant_scope method
      generate_scope_method(model, [path])
    else
      Rails.logger.info("TENANT ISOLATION FIX: For #{model.name}, consider adding a restaurant_id column and including TenantScoped")
      Rails.logger.info("TENANT ISOLATION FIX: Run: rails g migration AddRestaurantIdTo#{model.name.pluralize} restaurant:references")
    end
  end
  
  # Generate a with_restaurant_scope method based on the path to restaurant
  def self.generate_scope_method(model, path_array)
    Rails.logger.info("TENANT ISOLATION FIX: Add this custom with_restaurant_scope method:")
    Rails.logger.info("  def self.with_restaurant_scope")
    Rails.logger.info("    if ActiveRecord::Base.current_restaurant")
    
    # Build the joins and where clause based on the path
    if path_array.size == 1
      # Single association path
      assoc = path_array.first
      Rails.logger.info("      joins(:#{assoc}).where(#{assoc.to_s.pluralize}: { restaurant_id: ActiveRecord::Base.current_restaurant.id })")
    else
      # Multi-association path
      joins_clause = path_array.map { |a| ":#{a}" }.join(', ')
      last_assoc = path_array.last
      
      Rails.logger.info("      joins(#{joins_clause}).where(#{last_assoc.to_s.pluralize}: { restaurant_id: ActiveRecord::Base.current_restaurant.id })")
    end
    
    Rails.logger.info("    else")
    Rails.logger.info("      all")
    Rails.logger.info("    end")
    Rails.logger.info("  end")
  end
end
