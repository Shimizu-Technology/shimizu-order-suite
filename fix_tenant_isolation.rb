#!/usr/bin/env ruby
# Script to fix tenant isolation and CORS issues

puts "Starting tenant isolation and CORS fix script..."

# 1. Update allowed origins for Hafaloha restaurant
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

# 2. Update allowed origins for Shimizu Technology restaurant
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

# 3. Check and update public access settings for restaurant endpoints
restaurant_controller = RestaurantsController.new
if restaurant_controller.respond_to?(:global_access_permitted?)
  puts "✅ RestaurantsController has global_access_permitted? method"
  puts "Current global_access_permitted? actions: #{restaurant_controller.global_access_permitted? ? 'true' : 'false'}"
else
  puts "❌ RestaurantsController does not have global_access_permitted? method"
end

# 4. Check and update the CORS configuration
cors_config = Rails.application.config.middleware.find { |middleware| middleware.name == "Rack::Cors" }
if cors_config
  puts "✅ CORS middleware is configured"
else
  puts "❌ CORS middleware is not configured"
end

# 5. Check for any restaurant with public access disabled
Restaurant.all.each do |restaurant|
  puts "Restaurant: #{restaurant.name} (ID: #{restaurant.id})"
  puts "  Allowed origins: #{restaurant.allowed_origins.inspect}"
  
  # Check if any important origins are missing
  if restaurant.name == "Hafaloha"
    missing_origins = []
    missing_origins << "https://hafaloha-orders.com" unless restaurant.allowed_origins.include?("https://hafaloha-orders.com")
    missing_origins << "https://hafaloha.netlify.app" unless restaurant.allowed_origins.include?("https://hafaloha.netlify.app")
    
    if missing_origins.any?
      puts "  ❌ Missing important origins: #{missing_origins.join(', ')}"
    else
      puts "  ✅ All important origins are included"
    end
  elsif restaurant.name == "Shimizu Technology"
    missing_origins = []
    missing_origins << "https://shimizu-order-suite.netlify.app" unless restaurant.allowed_origins.include?("https://shimizu-order-suite.netlify.app")
    
    if missing_origins.any?
      puts "  ❌ Missing important origins: #{missing_origins.join(', ')}"
    else
      puts "  ✅ All important origins are included"
    end
  end
end

# 6. Check for any tenant isolation issues in the database
puts "\nChecking for tenant isolation issues..."

# Check if restaurant public endpoints are accessible
begin
  restaurant = Restaurant.first
  puts "✅ Can access Restaurant.first: #{restaurant.name}" if restaurant
rescue => e
  puts "❌ Error accessing Restaurant.first: #{e.message}"
end

puts "\nTenant isolation and CORS fix script completed."
