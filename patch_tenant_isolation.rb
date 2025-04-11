#!/usr/bin/env ruby
# Script to patch the tenant isolation mechanism for public access

puts "Starting tenant isolation patch script..."

# 1. First, let's check the current configuration
hafaloha = Restaurant.find_by(name: "Hafaloha")
shimizu = Restaurant.find_by(name: "Shimizu Technology")

puts "Hafaloha allowed origins: #{hafaloha&.allowed_origins.inspect}"
puts "Shimizu Technology allowed origins: #{shimizu&.allowed_origins.inspect}"

# 2. Create a patch for the TenantIsolation concern
# This is the critical part - we need to modify how it validates access for public endpoints

# First, let's check if we can find the TenantIsolation module
if defined?(TenantIsolation)
  puts "\nFound TenantIsolation module, creating patch..."
  
  # Create a patch class that will modify the TenantIsolation module
  module TenantIsolationPatch
    # This is the key method that's causing the 403 errors
    def validate_tenant_access(restaurant)
      # Check if this is a public endpoint request (no authentication)
      is_public_request = !current_user.present?
      
      # For public requests to public endpoints, allow access
      if is_public_request && request.headers['Origin'].present?
        origin = request.headers['Origin']
        puts "Checking origin: #{origin} for restaurant: #{restaurant&.id}"
        
        # Check if this origin is allowed for any restaurant
        if Restaurant.where("allowed_origins @> ARRAY[?]::varchar[]", [origin]).exists?
          puts "Origin #{origin} is allowed for some restaurant"
          return true
        end
      end
      
      # Allow access to global endpoints for super_admins
      return true if restaurant.nil? && global_access_permitted? && current_user&.role == "super_admin"
      
      # In development/test environments, be more permissive to make testing easier
      if Rails.env.development? || Rails.env.test?
        # Still log the access for debugging purposes
        log_tenant_access(restaurant) unless controller_name == "sessions" || controller_name == "passwords"
        return true
      end
      
      # Log tenant access for auditing purposes (if not an authentication endpoint)
      unless controller_name == "sessions" || controller_name == "passwords"
        log_tenant_access(restaurant)
      end
      
      # Allow super_admins to access any restaurant
      return true if current_user&.role == "super_admin"
      
      # Allow users to access their own restaurant
      return true if current_user&.restaurant_id == restaurant&.id
      
      # Special case for authentication endpoints
      return true if controller_name == "sessions" || controller_name == "passwords"
      
      # Special case for public endpoints - this is the key addition
      # If this is a public endpoint (like restaurant show) and the restaurant exists, allow access
      if global_access_permitted? && restaurant.present?
        puts "Allowing access to global endpoint: #{controller_name}##{action_name} for restaurant: #{restaurant.id}"
        return true
      end
      
      # If we get here, the user is trying to access a restaurant they don't have permission for
      # Log cross-tenant access attempt for security monitoring
      log_cross_tenant_access(restaurant&.id)
      
      raise TenantAccessDeniedError, "You don't have permission to access this restaurant's data"
    end
  end
  
  # Apply the patch to the TenantIsolation module
  TenantIsolation.prepend(TenantIsolationPatch)
  puts "✅ Applied patch to TenantIsolation module"
else
  puts "❌ Could not find TenantIsolation module"
end

# 3. Update the global_access_permitted? method for key controllers
# These controllers should allow public access to certain endpoints

# RestaurantsController
if defined?(RestaurantsController)
  puts "\nPatching RestaurantsController..."
  
  RestaurantsController.class_eval do
    # Override global_access_permitted? to allow public access to show action
    def global_access_permitted?
      # Allow public access to show, toggle_vip_mode, and set_current_event
      action_name.in?(["show", "toggle_vip_mode", "set_current_event"])
    end
  end
  
  puts "✅ Patched RestaurantsController"
end

# Admin::SiteSettingsController
if defined?(Admin::SiteSettingsController)
  puts "\nPatching Admin::SiteSettingsController..."
  
  Admin::SiteSettingsController.class_eval do
    # Allow public access to show action
    def global_access_permitted?
      action_name == "show"
    end
  end
  
  puts "✅ Patched Admin::SiteSettingsController"
end

# MenuItemsController
if defined?(MenuItemsController)
  puts "\nPatching MenuItemsController..."
  
  MenuItemsController.class_eval do
    # Allow public access to index and show actions
    def global_access_permitted?
      action_name.in?(["index", "show"])
    end
  end
  
  puts "✅ Patched MenuItemsController"
end

# MerchandiseCollectionsController
if defined?(MerchandiseCollectionsController)
  puts "\nPatching MerchandiseCollectionsController..."
  
  MerchandiseCollectionsController.class_eval do
    # Allow public access to index and show actions
    def global_access_permitted?
      action_name.in?(["index", "show"])
    end
  end
  
  puts "✅ Patched MerchandiseCollectionsController"
end

puts "\nTenant isolation patch completed."
puts "You will need to restart the server for these changes to take effect."
