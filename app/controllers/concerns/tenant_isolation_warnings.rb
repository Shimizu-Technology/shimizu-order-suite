# app/controllers/concerns/tenant_isolation_warnings.rb
#
# This module provides methods for warning about models that may not have
# proper tenant isolation. It's used by the TenantIsolation concern.
#
module TenantIsolationWarnings
  # Check for models that might not have proper tenant isolation
  # This helps identify potential tenant isolation issues during development
  def self.check_models(restaurant)
    # Skip checks in development and test environments
    return if Rails.env.test? || Rails.env.development?
    return unless restaurant.present?
    
    # Get the list of models with indirect tenant relationships
    indirect_tenant_models = Rails.application.config.indirect_tenant_models rescue []
    
    # Check each model for proper tenant isolation
    ApplicationRecord.descendants.each do |model|
      # Skip models we know have indirect tenant relationships
      next if indirect_tenant_models.include?(model.name)
      
      # Skip models that don't have a table yet (during migrations)
      next unless model.table_exists? rescue false
      
      # Skip STI child classes (they use the parent's table)
      next if model.superclass != ApplicationRecord && model.superclass < ApplicationRecord
      
      # Warn about models without restaurant_id column
      unless model.column_names.include?("restaurant_id")
        Rails.logger.warn("Model #{model.name} doesn't have restaurant_id column, tenant isolation may be compromised")
      end
    end
  end
end
