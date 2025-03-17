#!/usr/bin/env ruby
# script/verify_restaurant_settings.rb
require_relative '../config/environment'

puts "Verifying Restaurant admin_settings..."
puts "--------------------------------------"

# Check if all restaurants have admin_settings with email_header_color
missing_settings = []
invalid_settings = []

Restaurant.find_each do |restaurant|
  if restaurant.admin_settings.nil?
    missing_settings << "Restaurant ##{restaurant.id} (#{restaurant.name}) has nil admin_settings"
    next
  end

  unless restaurant.admin_settings.is_a?(Hash)
    invalid_settings << "Restaurant ##{restaurant.id} (#{restaurant.name}) has invalid admin_settings: #{restaurant.admin_settings.inspect}"
    next
  end

  unless restaurant.admin_settings.key?('email_header_color')
    missing_settings << "Restaurant ##{restaurant.id} (#{restaurant.name}) is missing email_header_color in admin_settings"
  end

  # Check if the color is the Hafaloha gold
  if restaurant.admin_settings.key?('email_header_color') &&
     restaurant.admin_settings['email_header_color'] != '#D4AF37'
    puts "Note: Restaurant ##{restaurant.id} (#{restaurant.name}) is using a custom color: #{restaurant.admin_settings['email_header_color']}"
  end
end

if missing_settings.any? || invalid_settings.any?
  puts "\n[!] Issues found:"

  if invalid_settings.any?
    puts "\nInvalid settings:"
    invalid_settings.each { |msg| puts "  - #{msg}" }
  end

  if missing_settings.any?
    puts "\nMissing settings:"
    missing_settings.each { |msg| puts "  - #{msg}" }
  end

  puts "\nTo fix these issues, run the following migration:"
  puts "  rails db:migrate"

  exit 1
else
  puts "\n[✓] All restaurants have valid admin_settings with email_header_color!"
end

# Check if the mailer_helper.rb file is using the correct method
mailer_helper_path = Rails.root.join('app/helpers/mailer_helper.rb')
if File.exist?(mailer_helper_path)
  content = File.read(mailer_helper_path)
  if content.include?('primary_color')
    puts "\n[!] Warning: mailer_helper.rb still contains references to primary_color"
    puts "    Please update the email_header_color_for method to remove this reference."
    exit 1
  else
    puts "\n[✓] mailer_helper.rb is correctly configured!"
  end
else
  puts "\n[!] Warning: mailer_helper.rb file not found"
end

puts "\nVerification completed successfully!"
