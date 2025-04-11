# app/services/feature_flag_service.rb
#
# The FeatureFlagService provides a clean API for checking feature flags
# throughout the application. It handles caching and fallbacks to ensure
# efficient feature flag lookups.
#
class FeatureFlagService
  # Cache TTL in seconds
  CACHE_TTL = 5.minutes.to_i
  
  # Check if a feature is enabled for a specific tenant
  # @param feature_name [String] The name of the feature to check
  # @param restaurant [Restaurant] The tenant to check the feature for
  # @return [Boolean] Whether the feature is enabled
  def self.enabled?(feature_name, restaurant = nil)
    # Use cache to avoid database lookups
    cache_key = cache_key_for(feature_name, restaurant&.id)
    
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      FeatureFlag.enabled?(feature_name, restaurant)
    end
  end
  
  # Get the configuration for a feature
  # @param feature_name [String] The name of the feature
  # @param restaurant [Restaurant] The tenant to get the configuration for
  # @param default [Hash] Default configuration to return if not found
  # @return [Hash] The feature configuration
  def self.configuration_for(feature_name, restaurant = nil, default = {})
    # Use cache to avoid database lookups
    cache_key = "#{cache_key_for(feature_name, restaurant&.id)}_config"
    
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      FeatureFlag.configuration_for(feature_name, restaurant, default)
    end
  end
  
  # Enable a feature for a specific tenant
  # @param feature_name [String] The name of the feature to enable
  # @param restaurant [Restaurant] The tenant to enable the feature for
  # @param configuration [Hash] Optional configuration for the feature
  # @return [FeatureFlag] The updated or created feature flag
  def self.enable_for_tenant(feature_name, restaurant, configuration = nil)
    result = FeatureFlag.enable_for_tenant(feature_name, restaurant, configuration)
    clear_cache_for(feature_name, restaurant.id)
    result
  end
  
  # Enable a feature globally
  # @param feature_name [String] The name of the feature to enable
  # @param configuration [Hash] Optional configuration for the feature
  # @return [FeatureFlag] The updated or created feature flag
  def self.enable_globally(feature_name, configuration = nil)
    result = FeatureFlag.enable_globally(feature_name, configuration)
    clear_cache_for(feature_name)
    result
  end
  
  # Disable a feature for a specific tenant
  # @param feature_name [String] The name of the feature to disable
  # @param restaurant [Restaurant] The tenant to disable the feature for
  # @return [FeatureFlag] The updated or created feature flag
  def self.disable_for_tenant(feature_name, restaurant)
    result = FeatureFlag.disable_for_tenant(feature_name, restaurant)
    clear_cache_for(feature_name, restaurant.id)
    result
  end
  
  # Disable a feature globally
  # @param feature_name [String] The name of the feature to disable
  # @return [FeatureFlag] The updated or created feature flag
  def self.disable_globally(feature_name)
    result = FeatureFlag.disable_globally(feature_name)
    clear_cache_for(feature_name)
    result
  end
  
  # Get all features for a specific tenant
  # @param restaurant [Restaurant] The tenant to get features for
  # @return [Hash] A hash of feature names to enabled status
  def self.all_features_for_tenant(restaurant)
    # Get tenant-specific flags
    tenant_flags = FeatureFlag.where(restaurant_id: restaurant.id).pluck(:name, :enabled).to_h
    
    # Get global flags
    global_flags = FeatureFlag.global.pluck(:name, :enabled).to_h
    
    # Merge global flags with tenant-specific overrides
    global_flags.merge(tenant_flags)
  end
  
  # Get all features in the system
  # @return [Array<FeatureFlag>] All feature flags in the system
  def self.all_features
    FeatureFlag.select(:name).distinct.pluck(:name)
  end
  
  # Get all tenants that have a specific feature enabled
  # @param feature_name [String] The name of the feature
  # @return [Array<Restaurant>] Tenants with the feature enabled
  def self.tenants_with_feature_enabled(feature_name)
    # Get IDs of tenants with the feature explicitly enabled
    tenant_ids = FeatureFlag.where(name: feature_name, enabled: true)
                           .where.not(restaurant_id: nil)
                           .pluck(:restaurant_id)
    
    # Check if the feature is globally enabled
    global_enabled = FeatureFlag.where(name: feature_name, global: true, enabled: true).exists?
    
    if global_enabled
      # If globally enabled, return all tenants except those with explicit overrides to disable
      excluded_tenant_ids = FeatureFlag.where(name: feature_name, enabled: false)
                                     .where.not(restaurant_id: nil)
                                     .pluck(:restaurant_id)
      
      Restaurant.where.not(id: excluded_tenant_ids)
    else
      # If not globally enabled, return only tenants with explicit enables
      Restaurant.where(id: tenant_ids)
    end
  end
  
  private
  
  # Generate a cache key for a feature flag
  # @param feature_name [String] The name of the feature
  # @param restaurant_id [Integer] The ID of the tenant
  # @return [String] The cache key
  def self.cache_key_for(feature_name, restaurant_id = nil)
    if restaurant_id
      "feature_flag:#{feature_name}:restaurant:#{restaurant_id}"
    else
      "feature_flag:#{feature_name}:global"
    end
  end
  
  # Clear cache for a feature flag
  # @param feature_name [String] The name of the feature
  # @param restaurant_id [Integer] The ID of the tenant (optional)
  def self.clear_cache_for(feature_name, restaurant_id = nil)
    if restaurant_id
      # Clear tenant-specific cache
      Rails.cache.delete(cache_key_for(feature_name, restaurant_id))
      Rails.cache.delete("#{cache_key_for(feature_name, restaurant_id)}_config")
    else
      # Clear global cache and all tenant-specific caches
      Rails.cache.delete(cache_key_for(feature_name))
      Rails.cache.delete("#{cache_key_for(feature_name)}_config")
      
      # This is a simplification - in a real system, you might want to use a pattern-based
      # cache deletion or maintain a list of tenants with this feature flag
    end
  end
end
