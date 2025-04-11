#!/usr/bin/env ruby
# Script to update allowed origins for restaurants

# Hafaloha restaurant
hafaloha = Restaurant.find_by(name: "Hafaloha")
if hafaloha
  hafaloha.update(
    allowed_origins: [
      "http://localhost:5173",
      "http://localhost:5174",
      "https://hafaloha-orders.com",
      "https://hafaloha.netlify.app",
      "https://hafaloha-lvmt0.kinsta.page"
    ]
  )
  puts "Updated allowed origins for Hafaloha"
else
  puts "Hafaloha restaurant not found"
end

# Shimizu Technology restaurant
shimizu = Restaurant.find_by(name: "Shimizu Technology")
if shimizu
  shimizu.update(
    allowed_origins: [
      "http://localhost:5175",
      "https://shimizu-order-suite.netlify.app"
    ]
  )
  puts "Updated allowed origins for Shimizu Technology"
else
  puts "Shimizu Technology restaurant not found"
end

puts "Done!"
