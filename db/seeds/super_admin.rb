# db/seeds/super_admin.rb
# Creates a super_admin user for development environments

# Only create the super_admin in development environment
if Rails.env.development?
  puts "== Creating development super_admin user =="
  
  # Default super_admin credentials for development
  dev_email = ENV['SUPER_ADMIN_EMAIL'] || 'super_admin@example.com'
  dev_password = ENV['SUPER_ADMIN_PASSWORD'] || 'password123'
  
  # Check if the super_admin already exists
  if User.exists?(email: dev_email, role: 'super_admin')
    puts "Super admin already exists with email: #{dev_email}"
  else
    # Create the super_admin user with nil restaurant_id
    super_admin = User.create!(
      email: dev_email,
      password: dev_password,
      first_name: 'Super',
      last_name: 'Admin',
      role: 'super_admin',
      restaurant_id: nil,
      phone_verified: true
    )
    
    puts "Created super_admin user:"
    puts "  Email: #{super_admin.email}"
    puts "  Password: #{dev_password} (only shown in development)"
    puts "  Role: #{super_admin.role}"
    puts "  Restaurant ID: #{super_admin.restaurant_id.inspect} (nil is correct for super_admin)"
    puts ""
    puts "NOTE: In production, super_admin users should be created via Rails console"
  end
end
