# db/seeds.rb
# Run: bin/rails db:seed
# If you want a fully clean DB each time, do:
#   rails db:drop db:create db:migrate db:seed

require 'active_record'

puts "== (Optional) Cleaning references =="
# Uncomment to truncate tables and reset IDs if needed:
# ActiveRecord::Base.connection.execute("
#   TRUNCATE reservations, waitlist_entries, users, restaurants, menus, menu_items,
#     layouts, seat_sections, seats, seat_allocations RESTART IDENTITY CASCADE
# ")

puts "== Seeding the database =="

# ------------------------------------------------------------------------------
# Force all parse/Time calls to treat times as Pacific/Guam
# so "17:00" is stored as 5 pm Guam.
# ------------------------------------------------------------------------------
Time.zone = "Pacific/Guam"

# ------------------------------------------------------------------------------
# 1) RESTAURANT
# ------------------------------------------------------------------------------
restaurant = Restaurant.find_or_create_by!(
  name: "Rotary Sushi",
  address: "744 N Marine Corps Dr, Harmon Industrial Park, 96913, Guam",
  layout_type: "sushi bar"
)

# Now explicitly parse "17:00" / "21:00" as Guam times.
restaurant.update!(
  opening_time:        Time.zone.parse("17:00"),  # 5:00 pm GUAM
  closing_time:        Time.zone.parse("21:00"),  # 9:00 pm GUAM
  time_slot_interval:  30,                        # e.g., every 30 mins in /availability
  time_zone:           "Pacific/Guam"             # store that the restaurant is in Guam
)

puts "Created/found Restaurant: #{restaurant.name}"
puts "   open from #{restaurant.opening_time.strftime("%H:%M")} to #{restaurant.closing_time.strftime("%H:%M")}"
puts "   time_slot_interval: #{restaurant.time_slot_interval} mins"
puts "   time_zone: #{restaurant.time_zone}"

# ------------------------------------------------------------------------------
# 2) USERS
# ------------------------------------------------------------------------------
admin_user = User.find_or_create_by!(email: "admin@example.com") do |u|
  u.first_name = "Admin"
  u.last_name  = "User"
  u.phone      = "671-123-9999"
  u.password   = "password"
  u.role       = "admin"
  u.restaurant_id = restaurant.id
end
puts "Created Admin User: #{admin_user.email} / password"

regular_user = User.find_or_create_by!(email: "user@example.com") do |u|
  u.first_name = "Regular"
  u.last_name  = "User"
  u.phone      = "671-555-1111"
  u.password   = "password"
  u.role       = "customer"   # or 'staff'
  u.restaurant_id = restaurant.id
end
puts "Created Regular User: #{regular_user.email} / password"

# ------------------------------------------------------------------------------
# 3) LAYOUT / SEAT SECTIONS / SEATS
# ------------------------------------------------------------------------------
main_layout = Layout.find_or_create_by!(
  name: "Main Sushi Layout",
  restaurant_id: restaurant.id
)

bar_section = SeatSection.find_or_create_by!(
  layout_id: main_layout.id,
  name:      "Sushi Bar Front",
  offset_x:  100,
  offset_y:  100,
  orientation: "vertical"
)

# We want 10 seats total, spaced 60px apart vertically
10.times do |i|
  seat_label = "Seat ##{i + 1}"
  Seat.find_or_create_by!(seat_section_id: bar_section.id, label: seat_label) do |seat|
    seat.position_x = 0
    # Increase this to 80 so each seat is 80px apart
    seat.position_y = 70 * i
    seat.capacity   = 1
  end
end

puts "Created 10 seats for Sushi Bar Front."

# Mark main_layout as the active layout for the restaurant
restaurant.update!(current_layout_id: main_layout.id)
puts "Set '#{main_layout.name}' as the current layout for Restaurant #{restaurant.id}."

# Build the sections_data JSON so the layout UI can display it
bar_section.reload  # ensure seats are loaded
section_hash = {
  "id"           => "section-bar-front",
  "name"         => bar_section.name,
  "type"         => bar_section.section_type.presence || "counter", # or "bar"
  "offsetX"      => bar_section.offset_x,
  "offsetY"      => bar_section.offset_y,
  "orientation"  => bar_section.orientation.presence || "vertical",
  "seats" => bar_section.seats.map do |s|
    {
      "label"       => s.label,
      "capacity"    => s.capacity,
      "position_x"  => s.position_x,
      "position_y"  => s.position_y
    }
  end
}
main_layout.update!(sections_data: { "sections" => [ section_hash ] })
puts "Updated Layout##{main_layout.id} sections_data with 1 seat section + 10 seats."

# ------------------------------------------------------------------------------
# 4) SEED Reservations in the 17:00-21:00 window
# ------------------------------------------------------------------------------
puts "Creating sample Reservations..."

# For example: 17:00 is 5pm Guam. We'll create some timeslots “today” + tomorrow.
today_17     = Time.zone.now.change(hour: 17, min: 0) # e.g. "today at 5 pm local"
today_18     = today_17 + 1.hour
today_19     = today_17 + 2.hours
tomorrow_17  = today_17 + 1.day

reservation_data = [
  { name: "Leon Shimizu",    start_time: today_17,    party_size: 2, status: "booked" },
  { name: "Kami Shimizu",    start_time: today_17,    party_size: 3, status: "booked" },
  { name: "Group of 2",      start_time: today_18,    party_size: 2, status: "booked" },
  { name: "Late Night Duo",  start_time: today_19,    party_size: 2, status: "booked" },
  { name: "Tomorrow Group",  start_time: tomorrow_17, party_size: 4, status: "booked" },
  { name: "Canceled Ex.",    start_time: tomorrow_17, party_size: 2, status: "canceled" },
]

reservation_data.each do |res_data|
  Reservation.find_or_create_by!(
    restaurant_id: restaurant.id,
    contact_name:  res_data[:name],
    start_time:    res_data[:start_time]
  ) do |res|
    res.party_size    = res_data[:party_size]
    res.contact_phone = "671-#{rand(100..999)}-#{rand(1000..9999)}"
    res.contact_email = "#{res_data[:name].parameterize}@example.com"
    res.status        = res_data[:status]
    # end_time = start_time + 60 minutes
    res.end_time      = res_data[:start_time] + 60.minutes
  end
end
puts "Reservations seeded."

# ------------------------------------------------------------------------------
# 5) SEED Some Waitlist Entries
# ------------------------------------------------------------------------------
puts "Creating sample Waitlist Entries..."

waitlist_data = [
  { name: "Walk-in Joe",       time: Time.zone.now,          party_size: 3, status: "waiting" },
  { name: "Party of Six",      time: Time.zone.now - 30*60,  party_size: 6, status: "waiting" },
  { name: "Seated Sarah",      time: Time.zone.now - 1.hour, party_size: 2, status: "seated" }
]

waitlist_data.each do |wl_data|
  WaitlistEntry.find_or_create_by!(
    restaurant_id: restaurant.id,
    contact_name:  wl_data[:name],
    check_in_time: wl_data[:time]
  ) do |w|
    w.party_size = wl_data[:party_size]
    w.status     = wl_data[:status]
  end
end
puts "Waitlist entries seeded."

# ------------------------------------------------------------------------------
# 6) MENUS & MENU ITEMS
# ------------------------------------------------------------------------------
main_menu = Menu.find_or_create_by!(
  name: "Main Menu",
  restaurant_id: restaurant.id
)
main_menu.update!(active: true)

if main_menu.menu_items.empty?
  MenuItem.create!(
    name: "Salmon Nigiri",
    description: "Fresh salmon on sushi rice",
    price: 3.50,
    menu: main_menu
  )
  MenuItem.create!(
    name: "Tuna Roll",
    description: "Classic tuna roll (6 pieces)",
    price: 5.00,
    menu: main_menu
  )
  MenuItem.create!(
    name: "Dragon Roll",
    description: "Eel, cucumber, avocado on top",
    price: 12.00,
    menu: main_menu
  )
  MenuItem.create!(
    name: "Tempura Udon",
    description: "Udon noodle soup with shrimp tempura",
    price: 10.50,
    menu: main_menu
  )
  puts "Created sample menu items on the main menu."
else
  puts "Main Menu items already exist."
end

puts "== Seeding complete! =="
