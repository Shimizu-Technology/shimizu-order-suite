namespace :multi_tenant do
  desc "Create test restaurants and users for multi-tenant testing"
  task setup_test_environment: :environment do
    puts "Setting up test environment for multi-tenant testing..."
    
    # Create three test restaurants
    restaurants = []
    
    3.times do |i|
      restaurant_name = "Test Restaurant #{i+1}"
      restaurant = Restaurant.find_or_create_by(name: restaurant_name) do |r|
        r.address = "#{i+1} Test Street, Test City"
        r.phone_number = "555-555-#{1000 + i}"
        r.contact_email = "test#{i+1}@example.com"
        r.time_zone = "Australia/Sydney"
        r.default_reservation_length = 60
        r.admin_settings = {
          "notification_channels" => {
            "orders" => {
              "web_push" => true
            }
          }
        }
        r.allowed_origins = ["https://test#{i+1}.example.com"]
        r.facebook_url = "https://facebook.com/test#{i+1}"
        r.instagram_url = "https://instagram.com/test#{i+1}"
        r.twitter_url = "https://twitter.com/test#{i+1}"
      end
      
      # Generate VAPID keys if needed
      if !restaurant.web_push_enabled?
        restaurant.generate_web_push_vapid_keys!
        puts "Generated VAPID keys for #{restaurant.name}"
      end
      
      restaurants << restaurant
      puts "Created restaurant: #{restaurant.name} (ID: #{restaurant.id})"
    end
    
    # Create admin users for each restaurant
    restaurants.each_with_index do |restaurant, i|
      admin_user = User.find_or_create_by(email: "admin#{i+1}@example.com") do |u|
        u.restaurant = restaurant
        u.first_name = "Admin"
        u.last_name = "User #{i+1}"
        u.password = "password123"
        u.password_confirmation = "password123"
        u.role = "admin"
      end
      puts "Created admin user for #{restaurant.name}: #{admin_user.email}"
      
      # Create regular users for each restaurant
      3.times do |j|
        regular_user = User.find_or_create_by(email: "user#{i+1}_#{j+1}@example.com") do |u|
          u.restaurant = restaurant
          u.first_name = "Regular"
          u.last_name = "User #{i+1}_#{j+1}"
          u.password = "password123"
          u.password_confirmation = "password123"
          u.role = "customer"
        end
        puts "Created regular user for #{restaurant.name}: #{regular_user.email}"
      end
      
      # Create staff user for each restaurant
      staff_user = User.find_or_create_by(email: "staff#{i+1}@example.com") do |u|
        u.restaurant = restaurant
        u.first_name = "Staff"
        u.last_name = "User #{i+1}"
        u.password = "password123"
        u.password_confirmation = "password123"
        u.role = "staff"
      end
      puts "Created staff user for #{restaurant.name}: #{staff_user.email}"
    end
    
    # Create a super_admin user with global access
    super_admin = User.find_or_create_by(email: "super_admin@example.com") do |u|
      u.first_name = "Super"
      u.last_name = "Admin"
      u.password = "password123"
      u.password_confirmation = "password123"
      u.role = "super_admin"
      # Super admin doesn't need a restaurant association
    end
    puts "Created super admin user: #{super_admin.email}"
    
    puts "Test environment setup complete!"
  end
  
  desc "Run multi-tenant isolation tests"
  task test_isolation: :environment do
    puts "Running multi-tenant isolation tests..."
    
    # Get the test restaurants
    restaurants = Restaurant.where("name LIKE 'Test Restaurant%'").order(:id).to_a
    
    if restaurants.size < 2
      puts "Error: Need at least 2 test restaurants. Run rake multi_tenant:setup_test_environment first."
      exit 1
    end
    
    restaurant1 = restaurants[0]
    restaurant2 = restaurants[1]
    
    puts "Testing isolation between #{restaurant1.name} (ID: #{restaurant1.id}) and #{restaurant2.name} (ID: #{restaurant2.id})"
    
    # Test user isolation
    puts "\nTesting User isolation..."
    ApplicationRecord.current_restaurant = restaurant1
    users_r1 = User.all.to_a
    puts "Users for #{restaurant1.name}: #{users_r1.size}"
    
    ApplicationRecord.current_restaurant = restaurant2
    users_r2 = User.all.to_a
    puts "Users for #{restaurant2.name}: #{users_r2.size}"
    
    # Check for overlap
    user_emails_r1 = users_r1.map(&:email)
    user_emails_r2 = users_r2.map(&:email)
    overlap = user_emails_r1 & user_emails_r2
    
    if overlap.empty?
      puts "✅ User isolation test passed: No user overlap between restaurants"
    else
      puts "❌ User isolation test failed: Found overlapping users: #{overlap.join(', ')}"
      puts "Note: super_admin users may appear in both lists"
    end
    
    # Clear the current restaurant to avoid affecting other operations
    ApplicationRecord.current_restaurant = nil
    
    puts "\nMulti-tenant isolation tests completed."
  end
end
