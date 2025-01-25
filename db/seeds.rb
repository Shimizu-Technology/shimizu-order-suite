# db/seeds.rb
# Run: bin/rails db:seed
# If you need a fully clean DB: rails db:drop db:create db:migrate db:seed

require 'active_record'

puts "== (Optional) Cleaning references =="
# Uncomment to truncate tables if you want a truly clean slate:
# ActiveRecord::Base.connection.execute("
#   TRUNCATE reservations, waitlist_entries, users, restaurants, menus, menu_items,
#     layouts, seat_sections, seats, seat_allocations RESTART IDENTITY CASCADE
# ")

puts "== Seeding the database =="

# ------------------------------------------------------------------------------
# Time zone
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
restaurant.update!(
  opening_time:        Time.zone.parse("17:00"),  # 5:00 pm GUAM
  closing_time:        Time.zone.parse("21:00"),  # 9:00 pm GUAM
  time_slot_interval:  30,
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

# --- A helper method to replicate your new "table" seat geometry ---
def layout_table_seats(seat_count, label_prefix)
  # Hardcode a simple circle: seat #1 at top, then clockwise
  angle_offset = -Math::PI / 2  # seat #1 at top
  angle_step   = (2 * Math::PI) / seat_count

  # For example:
  table_radius = 40
  seat_radius  = 32
  seat_margin  = 10
  radius       = table_radius + seat_radius + seat_margin  # ~82 px from center

  seats_data = []
  seat_count.times do |i|
    angle = angle_offset + i * angle_step
    x = radius * Math.cos(angle)
    y = radius * Math.sin(angle)
    seats_data << {
      label:    "#{label_prefix}#{i+1}",
      x:        x.round,
      y:        y.round,
      capacity: 1
    }
  end
  seats_data
end

# ----------------- SECTION 1: SUSHI BAR (COUNTER, FLOOR 1) -----------------
bar_section = SeatSection.find_or_create_by!(
  layout_id:    main_layout.id,
  name:         "Sushi Bar Front",
  section_type: "counter",
  orientation:  "vertical",
  offset_x:     100,
  offset_y:     100,
  floor_number: 1  # <--- ensures it's on floor 1
)

# We want 10 seats spaced ~70px apart vertically
10.times do |i|
  seat_label = "Seat ##{i + 1}"
  Seat.find_or_create_by!(seat_section_id: bar_section.id, label: seat_label) do |seat|
    seat.position_x = 0
    seat.position_y = 70 * i
    seat.capacity   = 1
  end
end
puts "Created 10 seats for Sushi Bar Front (Floor 1)."

# ----------------- SECTION 2: TABLE A (CIRCLE GEOMETRY, FLOOR 1) -----------------
table_section = SeatSection.find_or_create_by!(
  layout_id:    main_layout.id,
  name:         "Table A",
  section_type: "table",
  orientation:  "horizontal",
  offset_x:     400,
  offset_y:     100,
  floor_number: 1  # <--- also floor 1
)

# Create 4 seats in a circle so seat #1 is top, seat #2 is right, etc.
table_seats = layout_table_seats(4, "A")
table_seats.each do |ts|
  Seat.find_or_create_by!(seat_section_id: table_section.id, label: ts[:label]) do |seat|
    seat.position_x = ts[:x]
    seat.position_y = ts[:y]
    seat.capacity   = ts[:capacity]
  end
end
puts "Created 4 seats (circle) for Table A (Floor 1)."

# ----------------- SECTION 3: 2ND FLOOR LOUNGE (FLOOR 2) -----------------
lounge_section = SeatSection.find_or_create_by!(
  layout_id:    main_layout.id,
  name:         "2nd Floor Lounge",
  section_type: "table",
  orientation:  "horizontal",
  offset_x:     600,
  offset_y:     100,
  floor_number: 2  # <--- a second floor
)

# Create 4 seats in a line
4.times do |i|
  seat_label = "Lounge ##{i + 1}"
  Seat.find_or_create_by!(seat_section_id: lounge_section.id, label: seat_label) do |seat|
    seat.position_x = 70 * i
    seat.position_y = 0
    seat.capacity   = 1
  end
end
puts "Created 4 seats for 2nd Floor Lounge (Floor 2)."

# Mark main_layout as the active layout
restaurant.update!(current_layout_id: main_layout.id)
puts "Set '#{main_layout.name}' as the current layout for Restaurant #{restaurant.id}."

# ------------------------------------------------------------------------------
# Build out the sections_data JSON for the Layout
# We fetch from DB, transform it to match your React "sections" array
# ------------------------------------------------------------------------------
bar_section.reload
table_section.reload
lounge_section.reload

bar_section_hash = {
  "id"           => "section-bar-front",
  "name"         => bar_section.name,
  "type"         => bar_section.section_type || "counter",
  "offsetX"      => bar_section.offset_x,
  "offsetY"      => bar_section.offset_y,
  "orientation"  => bar_section.orientation || "vertical",
  "seats" => bar_section.seats.map do |s|
    {
      "label"       => s.label,
      "capacity"    => s.capacity,
      "position_x"  => s.position_x,
      "position_y"  => s.position_y
    }
  end
}

table_section_hash = {
  "id"           => "section-table-A",
  "name"         => table_section.name,
  "type"         => table_section.section_type || "table",
  "offsetX"      => table_section.offset_x,
  "offsetY"      => table_section.offset_y,
  "orientation"  => table_section.orientation || "horizontal",
  "seats" => table_section.seats.map do |s|
    {
      "label"       => s.label,
      "capacity"    => s.capacity,
      "position_x"  => s.position_x,
      "position_y"  => s.position_y
    }
  end
}

lounge_section_hash = {
  "id"           => "section-lounge",
  "name"         => lounge_section.name,
  "type"         => lounge_section.section_type || "table",
  "offsetX"      => lounge_section.offset_x,
  "offsetY"      => lounge_section.offset_y,
  "orientation"  => lounge_section.orientation || "horizontal",
  "seats" => lounge_section.seats.map do |s|
    {
      "label"       => s.label,
      "capacity"    => s.capacity,
      "position_x"  => s.position_x,
      "position_y"  => s.position_y
    }
  end
}

main_layout.update!(
  sections_data: {
    "sections" => [
      bar_section_hash,
      table_section_hash,
      lounge_section_hash
    ]
  }
)
puts "Updated Layout##{main_layout.id} sections_data with 3 seat sections (2 floors)."

# ------------------------------------------------------------------------------
# HELPER: Build seat preference arrays so each sub-array is exactly party_size seats
# We'll generate up to 3 sub-arrays if possible.
# ------------------------------------------------------------------------------
def build_seat_prefs_for_party_size(party_size, total_seats=10, max_sets=3)
  seat_labels = (1..total_seats).map { |i| "Seat ##{i}" }
  results = []
  idx = 0
  while idx + party_size <= seat_labels.size && results.size < max_sets
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

today_17    = Time.zone.now.change(hour: 17, min: 0)  # e.g. 17:00
today_18    = today_17 + 1.hour
today_19    = today_17 + 2.hours
tomorrow_17 = today_17 + 1.day

reservation_data = [
  {
    name:        "Leon Shimizu",
    start_time:  today_17,
    party_size:  2,
    status:      "booked",
    preferences: [["Seat #1", "Seat #2"], ["Seat #3"]]
  },
  {
    name:        "Kami Shimizu",
    start_time:  today_17,
    party_size:  3,
    status:      "booked",
    preferences: []
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
    preferences: [["Seat #3"]]
  },
  {
    name:        "Tomorrow Group",
    start_time:  tomorrow_17,
    party_size:  4,
    status:      "booked",
    preferences: [["Seat #6", "Seat #7"], ["Seat #8"]]
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
    res.party_size    = res_data[:party_size]
    res.contact_phone = "671-#{rand(100..999)}-#{rand(1000..9999)}"
    res.contact_email = "#{res_data[:name].parameterize}@example.com"
    res.status        = res_data[:status]
    res.end_time      = res_data[:start_time] + 60.minutes

    # Fix or generate seat_preferences so each sub-array has exactly party_size seats
    provided_prefs = res_data[:preferences] || []
    filtered = provided_prefs.select { |arr| arr.size == res_data[:party_size] }

    if filtered.size < 3
      auto_prefs = build_seat_prefs_for_party_size(res_data[:party_size])
      while filtered.size < 3 && !auto_prefs.empty?
        candidate = auto_prefs.shift
        filtered << candidate unless filtered.include?(candidate)
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
