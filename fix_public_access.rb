#!/usr/bin/env ruby
# Script to fix public access for frontend endpoints

puts "Starting public access fix script..."

# 1. Update allowed origins for both restaurants
hafaloha = Restaurant.find_by(name: "Hafaloha")
if hafaloha
  puts "Found Hafaloha restaurant (ID: #{hafaloha.id})"
  
  # Update allowed origins with all necessary domains
  hafaloha.update(
    allowed_origins: [
      "http://localhost:5173",
      "http://localhost:5174",
      "https://hafaloha-orders.com",
      "https://hafaloha.netlify.app",
      "https://hafaloha-lvmt0.kinsta.page"
    ]
  )
  puts "✅ Updated allowed origins for Hafaloha"
  puts "Current allowed origins: #{hafaloha.allowed_origins.inspect}"
else
  puts "❌ Hafaloha restaurant not found"
end

shimizu = Restaurant.find_by(name: "Shimizu Technology")
if shimizu
  puts "Found Shimizu Technology restaurant (ID: #{shimizu.id})"
  
  # Update allowed origins with all necessary domains
  shimizu.update(
    allowed_origins: [
      "http://localhost:5175",
      "https://shimizu-order-suite.netlify.app"
    ]
  )
  puts "✅ Updated allowed origins for Shimizu Technology"
  puts "Current allowed origins: #{shimizu.allowed_origins.inspect}"
else
  puts "❌ Shimizu Technology restaurant not found"
end

# 2. Update public access settings for controllers
# This is the critical part - we need to ensure that certain endpoints are accessible without authentication

# Find all controllers that include TenantIsolation
puts "\nUpdating public access settings for controllers..."

# Create a patch for RestaurantsController to allow public access to show endpoint
if defined?(RestaurantsController)
  puts "Patching RestaurantsController for public access..."
  
  # Check if the controller already has a global_access_permitted? method
  if RestaurantsController.instance_methods.include?(:global_access_permitted?)
    puts "✅ RestaurantsController already has global_access_permitted? method"
  else
    # Add the method if it doesn't exist
    RestaurantsController.class_eval do
      def global_access_permitted?
        action_name == "show"
      end
    end
    puts "✅ Added global_access_permitted? method to RestaurantsController"
  end
end

# Patch Admin::SiteSettingsController for public access
if defined?(Admin::SiteSettingsController)
  puts "Patching Admin::SiteSettingsController for public access..."
  
  Admin::SiteSettingsController.class_eval do
    def global_access_permitted?
      action_name == "show"
    end
  end
  puts "✅ Updated Admin::SiteSettingsController for public access"
end

# Patch MenuItemsController for public access
if defined?(MenuItemsController)
  puts "Patching MenuItemsController for public access..."
  
  MenuItemsController.class_eval do
    def global_access_permitted?
      action_name == "index" || action_name == "show"
    end
  end
  puts "✅ Updated MenuItemsController for public access"
end

# Patch MerchandiseCollectionsController for public access
if defined?(MerchandiseCollectionsController)
  puts "Patching MerchandiseCollectionsController for public access..."
  
  MerchandiseCollectionsController.class_eval do
    def global_access_permitted?
      action_name == "index" || action_name == "show"
    end
  end
  puts "✅ Updated MerchandiseCollectionsController for public access"
end

# 3. Update the TenantIsolation concern to be more lenient with public endpoints
if defined?(TenantIsolation)
  puts "\nPatching TenantIsolation concern..."
  
  # Monkey patch the validate_tenant_access method to be more lenient
  module TenantIsolation
    def validate_tenant_access(restaurant)
      # Allow access to global endpoints
      return true if restaurant.nil? && global_access_permitted?
      
      # In development/test environments, be more permissive
      if Rails.env.development? || Rails.env.test?
        return true
      end
      
      # Allow super_admins to access any restaurant
      return true if current_user&.role == "super_admin"
      
      # Allow users to access their own restaurant
      return true if current_user&.restaurant_id == restaurant&.id
      
      # Special case for authentication endpoints
      return true if controller_name == "sessions" || controller_name == "passwords"
      
      # Special case for public endpoints
      return true if global_access_permitted?
      
      # If we get here, the user is trying to access a restaurant they don't have permission for
      log_cross_tenant_access(restaurant&.id)
      
      raise TenantAccessDeniedError, "You don't have permission to access this restaurant's data"
    end
  end
  
  puts "✅ Updated TenantIsolation concern to be more lenient with public endpoints"
end

# 4. Reload routes to apply changes
begin
  Rails.application.reload_routes!
  puts "✅ Reloaded routes"
rescue => e
  puts "❌ Failed to reload routes: #{e.message}"
end

puts "\nPublic access fix script completed."
puts "You may need to restart the server for all changes to take effect."
