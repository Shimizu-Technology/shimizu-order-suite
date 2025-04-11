# app/models/feature_flag.rb
#
# The FeatureFlag model is used to manage feature flags in the application.
# It supports both global flags (affecting all tenants) and tenant-specific flags.
#
class FeatureFlag < ApplicationRecord
  include TenantScoped
  
  # Validations
  validates :name, presence: true, uniqueness: { scope: :restaurant_id }
  validates :enabled, inclusion: { in: [true, false] }
  validates :global, inclusion: { in: [true, false] }
  
  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :global, -> { where(global: true) }
  scope :tenant_specific, -> { where(global: false) }
  
  # Default values
  attribute :enabled, :boolean, default: false
  attribute :global, :boolean, default: false
  attribute :configuration, :jsonb, default: {}
  
  # Class methods for feature flag management
  
  # Check if a feature is enabled for a specific tenant
  # @param feature_name [String] The name of the feature to check
  # @param restaurant [Restaurant] The tenant to check the feature for
  # @return [Boolean] Whether the feature is enabled
  def self.enabled?(feature_name, restaurant = nil)
    # Check for a tenant-specific override first
    if restaurant.present?
      tenant_flag = find_by(name: feature_name, restaurant_id: restaurant.id)
      return tenant_flag.enabled if tenant_flag.present?
    end
    
    # Fall back to global flag
    global_flag = find_by(name: feature_name, global: true)
    global_flag&.enabled || false
  end
  
  # Get the configuration for a feature
  # @param feature_name [String] The name of the feature
  # @param restaurant [Restaurant] The tenant to get the configuration for
  # @param default [Hash] Default configuration to return if not found
  # @return [Hash] The feature configuration
  def self.configuration_for(feature_name, restaurant = nil, default = {})
    # Check for a tenant-specific configuration first
    if restaurant.present?
      tenant_flag = find_by(name: feature_name, restaurant_id: restaurant.id)
      return tenant_flag.configuration if tenant_flag.present? && tenant_flag.configuration.present?
    end
    
    # Fall back to global configuration
    global_flag = find_by(name: feature_name, global: true)
    global_flag&.configuration.presence || default
  end
  
  # Enable a feature for a specific tenant
  # @param feature_name [String] The name of the feature to enable
  # @param restaurant [Restaurant] The tenant to enable the feature for
  # @param configuration [Hash] Optional configuration for the feature
  # @return [FeatureFlag] The updated or created feature flag
  def self.enable_for_tenant(feature_name, restaurant, configuration = nil)
    flag = find_or_initialize_by(name: feature_name, restaurant_id: restaurant.id)
    flag.enabled = true
    flag.global = false
    flag.configuration = configuration if configuration.present?
    flag.save
    flag
  end
  
  # Enable a feature globally
  # @param feature_name [String] The name of the feature to enable
  # @param configuration [Hash] Optional configuration for the feature
  # @return [FeatureFlag] The updated or created feature flag
  def self.enable_globally(feature_name, configuration = nil)
    flag = find_or_initialize_by(name: feature_name, global: true)
    flag.enabled = true
    flag.restaurant_id = nil
    flag.configuration = configuration if configuration.present?
    flag.save
    flag
  end
  
  # Disable a feature for a specific tenant
  # @param feature_name [String] The name of the feature to disable
  # @param restaurant [Restaurant] The tenant to disable the feature for
  # @return [FeatureFlag] The updated or created feature flag
  def self.disable_for_tenant(feature_name, restaurant)
    flag = find_or_initialize_by(name: feature_name, restaurant_id: restaurant.id)
    flag.enabled = false
    flag.global = false
    flag.save
    flag
  end
  
  # Disable a feature globally
  # @param feature_name [String] The name of the feature to disable
  # @return [FeatureFlag] The updated or created feature flag
  def self.disable_globally(feature_name)
    flag = find_or_initialize_by(name: feature_name, global: true)
    flag.enabled = false
    flag.restaurant_id = nil
    flag.save
    flag
  end
end
