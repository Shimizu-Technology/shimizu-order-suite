#!/usr/bin/env ruby
# This script broadcasts test messages to WebSocket channels
# Usage: rails runner script/test_websocket.rb [restaurant_id]

require 'json'

# Get restaurant_id from command line or default to 1
restaurant_id = ARGV[0] || 1

# Create a test order
test_order = {
  id: 9999,
  restaurant_id: restaurant_id,
  status: 'pending',
  total: 25.99,
  items: [
    {
      id: 123,
      name: 'Test Item',
      price: 12.99,
      quantity: 2,
      customizations: {
        'Size' => 'Large',
        'Extras' => ['Cheese', 'Bacon']
      }
    }
  ],
  contact_name: 'Test Customer',
  contact_phone: '+1234567890',
  contact_email: 'test@example.com',
  created_at: Time.now.iso8601,
  updated_at: Time.now.iso8601,
  staff_created: false,
  global_last_acknowledged_at: nil
}

# Create a test inventory item
test_item = {
  id: 456,
  restaurant_id: restaurant_id,
  name: 'Test Inventory Item',
  price: 9.99,
  quantity: 2,
  low_stock_threshold: 5,
  category: 'Test Category',
  description: 'This is a test inventory item'
}

# Broadcast test order
puts "Broadcasting test order to order_channel_#{restaurant_id}..."
ActionCable.server.broadcast(
  "order_channel_#{restaurant_id}",
  {
    type: 'new_order',
    order: test_order
  }
)

# Wait a moment
sleep(1)

# Broadcast test inventory item
puts "Broadcasting test inventory item to inventory_channel_#{restaurant_id}..."
ActionCable.server.broadcast(
  "inventory_channel_#{restaurant_id}",
  {
    type: 'low_stock',
    item: test_item
  }
)

puts "Test broadcasts completed!"