namespace :multi_tenant do
  desc "Test multi-tenant isolation between existing restaurants"
  task test_isolation: :environment do
    puts "Testing multi-tenant isolation between existing restaurants..."
    
    # Get the existing restaurants - use unscoped to bypass tenant isolation
    restaurants = Restaurant.unscoped.all.to_a
    
    if restaurants.size < 2
      puts "Error: Need at least 2 restaurants in the database."
      exit 1
    end
    
    puts "Found #{restaurants.size} restaurants in the database."
    
    restaurant1 = restaurants[0] # Hafaloha
    restaurant2 = restaurants[1] # Shimizu Technology
    
    puts "Testing isolation between #{restaurant1.name} (ID: #{restaurant1.id}) and #{restaurant2.name} (ID: #{restaurant2.id})"
    
    # Create test users if they don't exist
    test_users = []
    
    # Create admin users for each restaurant if they don't exist
    restaurants.each_with_index do |restaurant, i|
      admin_email = "test_admin_#{restaurant.id}@example.com"
      admin_user = User.find_or_create_by(email: admin_email) do |u|
        u.restaurant = restaurant
        u.first_name = "Test Admin"
        u.last_name = restaurant.name
        u.password = "password123"
        u.password_confirmation = "password123"
        u.role = "admin"
      end
      puts "Admin user for #{restaurant.name}: #{admin_user.email}"
      test_users << admin_user
      
      # Create a regular user for each restaurant if they don't exist
      user_email = "test_user_#{restaurant.id}@example.com"
      regular_user = User.find_or_create_by(email: user_email) do |u|
        u.restaurant = restaurant
        u.first_name = "Test User"
        u.last_name = restaurant.name
        u.password = "password123"
        u.password_confirmation = "password123"
        u.role = "customer"
      end
      puts "Regular user for #{restaurant.name}: #{regular_user.email}"
      test_users << regular_user
    end
    
    # Create a super_admin user if it doesn't exist
    super_admin_email = "test_super_admin@example.com"
    super_admin = User.find_or_create_by(email: super_admin_email) do |u|
      u.first_name = "Test Super"
      u.last_name = "Admin"
      u.password = "password123"
      u.password_confirmation = "password123"
      u.role = "super_admin"
      # Super admin doesn't need a restaurant association
    end
    puts "Super admin user: #{super_admin.email}"
    test_users << super_admin
    
    # Test user isolation
    puts "\nTesting User isolation..."
    
    # Set current restaurant to restaurant1 (Hafaloha)
    ApplicationRecord.current_restaurant = restaurant1
    users_r1 = User.all.to_a
    puts "Users for #{restaurant1.name}: #{users_r1.size}"
    puts "User emails: #{users_r1.map(&:email).join(', ')}"
    
    # Set current restaurant to restaurant2 (Shimizu Technology)
    ApplicationRecord.current_restaurant = restaurant2
    users_r2 = User.all.to_a
    puts "Users for #{restaurant2.name}: #{users_r2.size}"
    puts "User emails: #{users_r2.map(&:email).join(', ')}"
    
    # Check for overlap (excluding super_admin)
    user_emails_r1 = users_r1.reject(&:super_admin?).map(&:email)
    user_emails_r2 = users_r2.reject(&:super_admin?).map(&:email)
    overlap = user_emails_r1 & user_emails_r2
    
    if overlap.empty?
      puts "✅ User isolation test passed: No user overlap between restaurants (excluding super_admin)"
    else
      puts "❌ User isolation test failed: Found overlapping users: #{overlap.join(', ')}"
    end
    
    # Test super_admin access
    puts "\nTesting Super Admin access..."
    ApplicationRecord.current_restaurant = nil
    super_admin_users = User.where(role: "super_admin").to_a
    puts "Super admin users: #{super_admin_users.map(&:email).join(', ')}"
    
    # Test Menu isolation
    puts "\nTesting Menu isolation..."
    
    # Create test menus if they don't exist
    restaurants.each do |restaurant|
      ApplicationRecord.current_restaurant = restaurant
      menu = Menu.find_or_create_by(name: "Test Menu for #{restaurant.name}") do |m|
        m.restaurant = restaurant
      end
      puts "Created test menu for #{restaurant.name}: #{menu.name}"
    end
    
    # Test menu isolation
    ApplicationRecord.current_restaurant = restaurant1
    menus_r1 = Menu.all.to_a
    puts "Menus for #{restaurant1.name}: #{menus_r1.size}"
    puts "Menu names: #{menus_r1.map(&:name).join(', ')}"
    
    ApplicationRecord.current_restaurant = restaurant2
    menus_r2 = Menu.all.to_a
    puts "Menus for #{restaurant2.name}: #{menus_r2.size}"
    puts "Menu names: #{menus_r2.map(&:name).join(', ')}"
    
    # Check for overlap
    menu_names_r1 = menus_r1.map(&:name)
    menu_names_r2 = menus_r2.map(&:name)
    menu_overlap = menu_names_r1 & menu_names_r2
    
    if menu_overlap.empty?
      puts "✅ Menu isolation test passed: No menu overlap between restaurants"
    else
      puts "❌ Menu isolation test failed: Found overlapping menus: #{menu_overlap.join(', ')}"
      puts "Note: This might be expected if menus have identical names across restaurants"
    end
    
    # Clear the current restaurant to avoid affecting other operations
    ApplicationRecord.current_restaurant = nil
    
    puts "\nMulti-tenant isolation tests completed."
  end
end
