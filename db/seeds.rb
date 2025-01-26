# db/seeds.rb

require 'active_record'

puts "== (Optional) Cleaning references =="
# Uncomment to truly reset all data (use with caution in production):
# ActiveRecord::Base.connection.execute("
#   TRUNCATE reservations, waitlist_entries, users, restaurants, menus, menu_items,
#     layouts, seat_sections, seats, seat_allocations, operating_hours RESTART IDENTITY CASCADE
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
  time_slot_interval:         30,
  time_zone:                  "Pacific/Guam",
  default_reservation_length: 60,
  admin_settings: {
    "require_deposit" => false,
    "deposit_amount"  => 0
    # add any other placeholders if you want
  }
)

puts "Created/found Restaurant: #{restaurant.name}"
puts "   time_slot_interval: #{restaurant.time_slot_interval} mins"
puts "   time_zone: #{restaurant.time_zone}"
puts "   default_reservation_length: #{restaurant.default_reservation_length}"
puts "   admin_settings: #{restaurant.admin_settings.inspect}"

# ------------------------------------------------------------------------------
# 1B) SEED OPERATING HOURS (Sunday..Saturday)
# ------------------------------------------------------------------------------
# Example schedule: Sunday closed, Mon-Fri = 9:00–21:00, Sat = 10:00–22:00
oh_data = [
  { day_of_week: 0, open_time: nil,       close_time: nil,       closed: true  },  # Sunday
  { day_of_week: 1, open_time: "09:00:00", close_time: "21:00:00", closed: false }, # Monday
  { day_of_week: 2, open_time: "09:00:00", close_time: "21:00:00", closed: false }, # Tuesday
  { day_of_week: 3, open_time: "09:00:00", close_time: "21:00:00", closed: false }, # Wed
  { day_of_week: 4, open_time: "09:00:00", close_time: "21:00:00", closed: false }, # Thu
  { day_of_week: 5, open_time: "09:00:00", close_time: "21:00:00", closed: false }, # Fri
  { day_of_week: 6, open_time: "10:00:00", close_time: "22:00:00", closed: false }  # Saturday
]

oh_data.each do |row|
  oh = OperatingHour.find_or_create_by!(
    restaurant_id: restaurant.id,
    day_of_week:   row[:day_of_week]
  ) do |oh_record|
    oh_record.open_time  = row[:open_time]
    oh_record.close_time = row[:close_time]
    oh_record.closed     = row[:closed]
  end

  # If the record already existed, update it to match new times if needed
  oh.update!(open_time: row[:open_time], close_time: row[:close_time], closed: row[:closed]) unless oh.new_record?

  # Print summary
  day_name = Date::DAYNAMES[row[:day_of_week]]  # e.g. "Sunday"
  if oh.closed?
    puts " - #{day_name} => CLOSED"
  else
    puts " - #{day_name} => #{oh.open_time.strftime("%H:%M")} to #{oh.close_time.strftime("%H:%M")}"
  end
end

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

# --- A helper method to replicate a simple table geometry in a circle ---
def layout_table_seats(seat_count, label_prefix)
  # seat #1 at top, then clockwise
  angle_offset = -Math::PI / 2
  angle_step   = (2 * Math::PI) / seat_count

  table_radius = 40
  seat_radius  = 32
  seat_margin  = 10
  radius       = table_radius + seat_radius + seat_margin  # ~82 from center

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

# ----------------- SECTION 1: SUSHI BAR FRONT (COUNTER, FLOOR 1) -----------------
bar_section = SeatSection.find_or_create_by!(
  layout_id:    main_layout.id,
  name:         "Sushi Bar Front",
  section_type: "counter",
  orientation:  "vertical",
  offset_x:     100,
  offset_y:     100,
  floor_number: 1
)

# We create 10 seats spaced ~70px vertically
10.times do |i|
  seat_label = "Seat ##{i + 1}"
  Seat.find_or_create_by!(seat_section_id: bar_section.id, label: seat_label) do |seat|
    seat.position_x = 0
    seat.position_y = 70 * i
    seat.capacity   = 1
  end
end
puts "Created 10 seats for Sushi Bar Front (Floor 1)."

# ----------------- SECTION 2: TABLE A (CIRCLE, FLOOR 1) -----------------
table_a = SeatSection.find_or_create_by!(
  layout_id:    main_layout.id,
  name:         "Table A",
  section_type: "table",
  orientation:  "horizontal",
  offset_x:     400,
  offset_y:     100,
  floor_number: 1
)

table_seats = layout_table_seats(4, "A")  # e.g. A1, A2, A3, A4
table_seats.each do |ts|
  Seat.find_or_create_by!(seat_section_id: table_a.id, label: ts[:label]) do |seat|
    seat.position_x = ts[:x]
    seat.position_y = ts[:y]
    seat.capacity   = ts[:capacity]
  end
end
puts "Created 4 seats in a circle for Table A (Floor 1)."

# ----------------- SECTION 3: TABLE 4 (FLOOR 2) -----------------
table_4 = SeatSection.find_or_create_by!(
  layout_id:    main_layout.id,
  name:         "Table 4",
  section_type: "table",
  orientation:  "horizontal",
  offset_x:     237,
  offset_y:     223,
  floor_number: 2
)

# Another circle of 4 seats
table_4_seats = layout_table_seats(4, "T4-")
table_4_seats.each do |ts|
  Seat.find_or_create_by!(seat_section_id: table_4.id, label: ts[:label]) do |seat|
    seat.position_x = ts[:x]
    seat.position_y = ts[:y]
    seat.capacity   = ts[:capacity]
  end
end
puts "Created 4 seats in a circle for Table 4 (Floor 2)."

# Mark main_layout as the active layout
restaurant.update!(current_layout_id: main_layout.id)
puts "Set '#{main_layout.name}' as the current layout for Restaurant #{restaurant.id}."

# ------------------------------------------------------------------------------
# Build sections_data JSON for the Layout
# So your React front-end can read the floorNumber, seats, etc.
# ------------------------------------------------------------------------------
bar_section.reload
table_a.reload
table_4.reload

bar_section_hash = {
  "id"           => "1",
  "name"         => bar_section.name,
  "type"         => bar_section.section_type,
  "offsetX"      => bar_section.offset_x,
  "offsetY"      => bar_section.offset_y,
  "floorNumber"  => bar_section.floor_number,
  "orientation"  => bar_section.orientation,
  "seats" => bar_section.seats.map do |s|
    {
      "id"          => s.id,
      "label"       => s.label,
      "capacity"    => s.capacity,
      "position_x"  => s.position_x,
      "position_y"  => s.position_y
    }
  end
}

table_a_hash = {
  "id"           => "2",
  "name"         => table_a.name,
  "type"         => table_a.section_type,
  "offsetX"      => table_a.offset_x,
  "offsetY"      => table_a.offset_y,
  "floorNumber"  => table_a.floor_number,
  "orientation"  => table_a.orientation,
  "seats" => table_a.seats.map do |s|
    {
      "id"          => s.id,
      "label"       => s.label,
      "capacity"    => s.capacity,
      "position_x"  => s.position_x,
      "position_y"  => s.position_y
    }
  end
}

table_4_hash = {
  "id"           => "section-4",
  "name"         => table_4.name,
  "type"         => table_4.section_type,
  "offsetX"      => table_4.offset_x,
  "offsetY"      => table_4.offset_y,
  "floorNumber"  => table_4.floor_number,
  "orientation"  => table_4.orientation,
  "seats" => table_4.seats.map do |s|
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
      table_a_hash,
      table_4_hash
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

now         = Time.current
today_17    = now.change(hour: 17, min: 0)
today_18    = today_17 + 1.hour
today_19    = today_17 + 2.hours
tomorrow_17 = today_17 + 1.day

reservation_data = [
  {
    name:        "Leon",
    start_time:  today_17,
    party_size:  2,
    status:      "booked",
    preferences: [["Seat #5", "Seat #6"]]
  },
  {
    name:        "Kami",
    start_time:  today_17,
    party_size:  3,
    status:      "booked",
    preferences: [["Seat #7", "Seat #8", "Seat #9"]]
  },
  {
    name:        "Group of Two",
    start_time:  today_18,
    party_size:  2,
    status:      "booked",
    preferences: [["A1", "A2"]]
  },
  {
    name:        "Late Nighters",
    start_time:  today_19,
    party_size:  2,
    status:      "booked",
    preferences: [["A3","A4"]]
  },
  {
    name:        "Tomorrow Group",
    start_time:  tomorrow_17,
    party_size:  4,
    status:      "booked",
    preferences: [["Seat #2","Seat #3","Seat #4","Seat #9"]]
  },
  {
    name:        "Canceled Example",
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

    # Possibly auto-generate more seat sets
    provided_prefs = res_data[:preferences] || []
    # only keep valid sets that match the party_size exactly
    filtered = provided_prefs.select { |arr| arr.size == res_data[:party_size] }

    if filtered.size < 3
      auto_prefs = build_seat_prefs_for_party_size(res_data[:party_size], 10)
      while filtered.size < 3 && !auto_prefs.empty?
        candidate = auto_prefs.shift
        # only add it if not already included
        filtered << candidate unless filtered.any? { |pref| pref.sort == candidate.sort }
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
  { name: "Walk-in Joe",       time: now,                party_size: 3, status: "waiting" },
  { name: "Party of Six",      time: now - 30*60,        party_size: 6, status: "waiting" },
  { name: "Sarah",             time: now - 1.hour,       party_size: 2, status: "waiting" },
  { name: "Walk-in Solo",      time: now - 15*60,        party_size: 1, status: "waiting" }
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
  puts "Created sample menu items on the Main Menu."
else
  puts "Main Menu items already exist."
end

puts "== Seeding complete! =="
