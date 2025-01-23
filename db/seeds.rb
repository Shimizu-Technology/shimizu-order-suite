# db/seeds.rb
# Run: bin/rails db:seed
# (If you want a fully clean DB each time, do:
#   rails db:drop db:create db:migrate db:seed)

require 'active_record'

puts "== (Optional) Cleaning references =="
# Uncomment to truncate tables and reset IDs if needed:
# ActiveRecord::Base.connection.execute("
#   TRUNCATE reservations, waitlist_entries, users, restaurants, menus, menu_items,
#     layouts, seat_sections, seats, seat_allocations RESTART IDENTITY CASCADE
# ")

puts "== Seeding the database =="

# ------------------------------------------------------------------------------
# Force parse/Time calls to treat times as Pacific/Guam
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

# Now explicitly parse "17:00"/"21:00" as Guam times:
restaurant.update!(
  opening_time:        Time.zone.parse("17:00"),  # 5:00 pm GUAM
  closing_time:        Time.zone.parse("21:00"),  # 9:00 pm GUAM
  time_slot_interval:  30,                        # e.g. every 30 mins in /availability
  time_zone:           "Pacific/Guam"
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

# We want 10 seats total, spaced ~70px apart vertically
10.times do |i|
  seat_label = "Seat ##{i + 1}"
  Seat.find_or_create_by!(seat_section_id: bar_section.id, label: seat_label) do |seat|
    seat.position_x = 0
    seat.position_y = 70 * i
    seat.capacity   = 1
  end
end
puts "Created 10 seats for Sushi Bar Front."

# Mark main_layout as the active layout
restaurant.update!(current_layout_id: main_layout.id)
puts "Set '#{main_layout.name}' as the current layout for Restaurant #{restaurant.id}."

# Build sections_data JSON for the layout UI
bar_section.reload
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
# HELPER: Build seat preference arrays so each sub-array is exactly party_size seats
# We have up to 10 seats labeled "Seat #1" .. "Seat #10"
# We'll generate up to 3 sub-arrays if possible.
# ------------------------------------------------------------------------------
def build_seat_prefs_for_party_size(party_size, total_seats=10, max_sets=3)
  seat_labels = (1..total_seats).map{|i| "Seat ##{i}"}
  results = []
  idx = 0
  while idx + party_size <= seat_labels.size && results.size < max_sets
    # slice out exactly 'party_size' seats
    subset = seat_labels[idx...(idx + party_size)]
    results << subset
    idx += party_size
  end
  results
end

# ------------------------------------------------------------------------------
# 4) SEED Reservations
# ------------------------------------------------------------------------------
puts "Creating sample Reservations..."

today_17     = Time.zone.now.change(hour: 17, min: 0)
today_18     = today_17 + 1.hour
today_19     = today_17 + 2.hours
tomorrow_17  = today_17 + 1.day

reservation_data = [
  {
    name:        "Leon Shimizu",
    start_time:  today_17,
    party_size:  2,
    status:      "booked",
    # e.g. seat_prefs
    preferences: [["Seat #1", "Seat #2"], ["Seat #3"]]
  },
  {
    name:        "Kami Shimizu",
    start_time:  today_17,
    party_size:  3,
    status:      "booked",
    preferences: [] # no prefs => we'll fill them
  },
  {
    name:        "Group of 2",
    start_time:  today_18,
    party_size:  2,
    status:      "booked",
    preferences: [["Seat #4", "Seat #5"]]
  },
  {
    name:        "Late Night Duo",
    start_time:  today_19,
    party_size:  2,
    status:      "booked",
    preferences: [["Seat #3"]] # invalid sub-array => we'll fix
  },
  {
    name:        "Tomorrow Group",
    start_time:  tomorrow_17,
    party_size:  4,
    status:      "booked",
    preferences: [["Seat #6", "Seat #7"], ["Seat #8"]] # second is only 1 seat => fix
  },
  {
    name:        "Canceled Ex.",
    start_time:  tomorrow_17,
    party_size:  2,
    status:      "canceled",
    preferences: []
  },
]

reservation_data.each do |res_data|
  Reservation.find_or_create_by!(
    restaurant_id: restaurant.id,
    contact_name:  res_data[:name],
    start_time:    res_data[:start_time]
  ) do |res|
    res.party_size     = res_data[:party_size]
    res.contact_phone  = "671-#{rand(100..999)}-#{rand(1000..9999)}"
    res.contact_email  = "#{res_data[:name].parameterize}@example.com"
    res.status         = res_data[:status]
    res.end_time       = res_data[:start_time] + 60.minutes

    # Fix or generate seat_preferences to ensure each sub-array has exactly party_size seats
    provided_prefs = res_data[:preferences] || []
    # 1) Filter out any sub-arrays not matching party_size
    filtered = provided_prefs.select {|arr| arr.size == res_data[:party_size] }

    # 2) If we have fewer than 1–3 sets, fill the remainder
    if filtered.size < 3
      auto_prefs = build_seat_prefs_for_party_size(res_data[:party_size])
      # Merge auto_prefs with the existing filtered, but avoid duplicates
      # or you could just override if you prefer
      while filtered.size < 3 && !auto_prefs.empty?
        # pop the first from auto_prefs
        candidate = auto_prefs.shift
        # ensure we haven't used that exact set
        unless filtered.include?(candidate)
          filtered << candidate
        end
      end
    end

    res.seat_preferences = filtered
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
