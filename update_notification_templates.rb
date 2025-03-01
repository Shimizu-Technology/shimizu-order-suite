#!/usr/bin/env ruby
# This script updates the default notification templates to add the 'hafaloha' frontend_id

# Find all default templates (with restaurant_id = nil)
default_templates = NotificationTemplate.where(restaurant_id: nil)

puts "Found #{default_templates.count} default templates"

# Update these templates to add frontend_id = 'hafaloha'
default_templates.each do |template|
  # Update the template to set frontend_id = 'hafaloha'
  template.update!(frontend_id: 'hafaloha')
  puts "Updated template for #{template.notification_type} (#{template.channel}) with frontend_id 'hafaloha'"
end

puts "Done!"
