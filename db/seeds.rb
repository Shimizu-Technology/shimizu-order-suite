# db/seeds.rb

require 'active_record'

# Tell Rails to reload the actual DB columns from scratch
Reservation.reset_column_information

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
  name: "Hafaloha"
) do |r|
  r.address     = "955 Pale San Vitores Rd, Tamuning, Guam 96913"
  r.layout_type = "seat-based"
end

restaurant.update!(
  address:                   "955 Pale San Vitores Rd, Tamuning, Guam 96913",
  time_slot_interval:        30,
  time_zone:                 "Pacific/Guam",
  default_reservation_length: 60,
  admin_settings: {
    "require_deposit" => false,
    "deposit_amount"  => 0
  }
)

puts "Created/found Restaurant: #{restaurant.name}"
puts "   Address:  #{restaurant.address}"
puts "   time_slot_interval: #{restaurant.time_slot_interval} mins"
puts "   time_zone: #{restaurant.time_zone}"
puts "   default_reservation_length: #{restaurant.default_reservation_length}"
puts "   admin_settings: #{restaurant.admin_settings.inspect}"

# ------------------------------------------------------------------------------
# 1B) SEED OPERATING HOURS
#
# Sunday is day_of_week=0, Monday=1, Tuesday=2, etc.
# Requested hours:
#   * Tues–Thu: 11AM–9PM
#   * Fri–Sat: 11AM–10PM
#   * Sun: 11AM–9PM
#   * Mon: closed
# ------------------------------------------------------------------------------
oh_data = [
  # Sunday (day_of_week=0) => 11:00–21:00
  { day_of_week: 0, open_time: "11:00:00", close_time: "21:00:00", closed: false },
  # Monday (1) => closed
  { day_of_week: 1, open_time: nil,        close_time: nil,        closed: true },
  # Tuesday (2) => 11:00–21:00
  { day_of_week: 2, open_time: "11:00:00", close_time: "21:00:00", closed: false },
  # Wednesday (3) => 11:00–21:00
  { day_of_week: 3, open_time: "11:00:00", close_time: "21:00:00", closed: false },
  # Thursday (4) => 11:00–21:00
  { day_of_week: 4, open_time: "11:00:00", close_time: "21:00:00", closed: false },
  # Friday (5) => 11:00–22:00
  { day_of_week: 5, open_time: "11:00:00", close_time: "22:00:00", closed: false },
  # Saturday (6) => 11:00–22:00
  { day_of_week: 6, open_time: "11:00:00", close_time: "22:00:00", closed: false }
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

  # If the record already existed, update it
  oh.update!(
    open_time:  row[:open_time],
    close_time: row[:close_time],
    closed:     row[:closed]
  ) unless oh.new_record?

  day_name = Date::DAYNAMES[row[:day_of_week]]
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
  u.role       = "customer"
  u.restaurant_id = restaurant.id
end
puts "Created Regular User: #{regular_user.email} / password"

# ------------------------------------------------------------------------------
# 3) LAYOUT / SEAT SECTIONS / SEATS
# ------------------------------------------------------------------------------
main_layout = Layout.find_or_create_by!(name: "Main Layout", restaurant_id: restaurant.id)

# Example circle‐table helper:
def layout_table_seats(seat_count, label_prefix)
  angle_offset = -Math::PI / 2
  angle_step   = (2 * Math::PI) / seat_count
  table_radius = 40
  seat_radius  = 32
  seat_margin  = 10
  radius       = table_radius + seat_radius + seat_margin

  seats_data = []
  seat_count.times do |i|
    angle = angle_offset + i * angle_step
    x     = radius * Math.cos(angle)
    y     = radius * Math.sin(angle)
    seats_data << {
      label:    "#{label_prefix}#{i+1}",
      x:        x.round,
      y:        y.round,
      capacity: 1
    }
  end
  seats_data
end

# SECTION 1
bar_section = SeatSection.find_or_create_by!(
  layout_id:    main_layout.id,
  name:         "Front Counter",
  section_type: "counter",
  orientation:  "vertical",
  offset_x:     100,
  offset_y:     100,
  floor_number: 1
)

10.times do |i|
  seat_label = "Seat ##{i + 1}"
  Seat.find_or_create_by!(seat_section_id: bar_section.id, label: seat_label) do |seat|
    seat.position_x = 0
    seat.position_y = 70 * i
    seat.capacity   = 1
    # Removed any `seat.status` references, as that column no longer exists
  end
end
puts "Created 10 seats for Front Counter (Floor 1)."

# SECTION 2: Table A (circle)
table_a = SeatSection.find_or_create_by!(
  layout_id:    main_layout.id,
  name:         "Table A",
  section_type: "table",
  orientation:  "horizontal",
  offset_x:     400,
  offset_y:     100,
  floor_number: 1
)

layout_table_seats(4, "A").each do |ts|
  Seat.find_or_create_by!(seat_section_id: table_a.id, label: ts[:label]) do |seat|
    seat.position_x = ts[:x]
    seat.position_y = ts[:y]
    seat.capacity   = ts[:capacity]
  end
end
puts "Created 4 seats in a circle for Table A (Floor 1)."

# SECTION 3: Another table on Floor 2
table_2 = SeatSection.find_or_create_by!(
  layout_id:    main_layout.id,
  name:         "Table 2 (Upstairs)",
  section_type: "table",
  orientation:  "horizontal",
  offset_x:     237,
  offset_y:     223,
  floor_number: 2
)

layout_table_seats(4, "T2-").each do |ts|
  Seat.find_or_create_by!(seat_section_id: table_2.id, label: ts[:label]) do |seat|
    seat.position_x = ts[:x]
    seat.position_y = ts[:y]
    seat.capacity   = ts[:capacity]
  end
end
puts "Created 4 seats in a circle for Table 2 (Floor 2)."

# Mark main_layout as active
restaurant.update!(current_layout_id: main_layout.id)
puts "Set '#{main_layout.name}' as the current layout for Restaurant #{restaurant.id}."

# Build sections_data JSON for the Layout
bar_section.reload
table_a.reload
table_2.reload

bar_section_hash = {
  "id"           => bar_section.id.to_s,
  "name"         => bar_section.name,
  "type"         => bar_section.section_type,
  "offsetX"      => bar_section.offset_x,
  "offsetY"      => bar_section.offset_y,
  "floorNumber"  => bar_section.floor_number,
  "orientation"  => bar_section.orientation,
  "seats" => bar_section.seats.map do |s|
    {
      "id"         => s.id,
      "label"      => s.label,
      "capacity"   => s.capacity,
      "position_x" => s.position_x,
      "position_y" => s.position_y
    }
  end
}

table_a_hash = {
  "id"           => table_a.id.to_s,
  "name"         => table_a.name,
  "type"         => table_a.section_type,
  "offsetX"      => table_a.offset_x,
  "offsetY"      => table_a.offset_y,
  "floorNumber"  => table_a.floor_number,
  "orientation"  => table_a.orientation,
  "seats" => table_a.seats.map do |s|
    {
      "id"         => s.id,
      "label"      => s.label,
      "capacity"   => s.capacity,
      "position_x" => s.position_x,
      "position_y" => s.position_y
    }
  end
}

table_2_hash = {
  "id"           => table_2.id.to_s,
  "name"         => table_2.name,
  "type"         => table_2.section_type,
  "offsetX"      => table_2.offset_x,
  "offsetY"      => table_2.offset_y,
  "floorNumber"  => table_2.floor_number,
  "orientation"  => table_2.orientation,
  "seats" => table_2.seats.map do |s|
    {
      "label"      => s.label,
      "capacity"   => s.capacity,
      "position_x" => s.position_x,
      "position_y" => s.position_y
    }
  end
}

main_layout.update!(
  sections_data: {
    "sections" => [bar_section_hash, table_a_hash, table_2_hash]
  }
)
puts "Updated Layout##{main_layout.id} sections_data with seat sections."

# ------------------------------------------------------------------------------
# HELPER: seat preference arrays
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

    provided_prefs = res_data[:preferences] || []
    filtered = provided_prefs.select { |arr| arr.size == res_data[:party_size] }

    if filtered.size < 3
      auto_prefs = build_seat_prefs_for_party_size(res_data[:party_size], 10)
      while filtered.size < 3 && !auto_prefs.empty?
        candidate = auto_prefs.shift
        # only add if not already included
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
  { name: "Walk-in Joe",       time: now,          party_size: 3, status: "waiting" },
  { name: "Party of Six",      time: now - 30*60,  party_size: 6, status: "waiting" },
  { name: "Sarah",             time: now - 1.hour, party_size: 2, status: "waiting" },
  { name: "Walk-in Solo",      time: now - 15*60,  party_size: 1, status: "waiting" }
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
categories_data = [
  {
    id: 'appetizers',
    name: 'Appetizers',
    description: 'Start your meal with these island favorites'
  },
  {
    id: 'poke',
    name: 'Poke Bowls',
    description: 'Fresh Hawaiian-style fish with your choice of toppings'
  },
  {
    id: 'burgers',
    name: 'Island Burgers',
    description: 'Signature burgers with a tropical twist'
  },
  {
    id: 'desserts',
    name: 'Desserts',
    description: 'Cool down with our tropical treats'
  },
  {
    id: 'drinks',
    name: 'Drinks',
    description: 'Refresh yourself with island beverages'
  }
]

# Hardcode all images to this single S3 URL:
s3_image_url = "https://hafaloha.s3.ap-southeast-2.amazonaws.com/Hafaloha_Burger.webp"

menu_items_data = [
  # (Data omitted for brevity—no change, just removing seat.status lines)
  # ...
]

puts "Creating Main Menu with categories & items..."

main_menu = Menu.find_or_create_by!(name: "Main Menu", restaurant_id: restaurant.id)
main_menu.update!(active: true)

menu_items_data.each do |item_data|
  MenuItem.find_or_create_by!(menu_id: main_menu.id, name: item_data[:name]) do |mi|
    mi.description = item_data[:description]
    mi.price       = item_data[:price]
    mi.category    = item_data[:category]
    # Force the same S3 URL for all seeds:
    mi.image_url   = s3_image_url
    mi.available   = true
  end
end

puts "Seeded #{MenuItem.count} menu items under '#{main_menu.name}'."

# ------------------------------------------------------------------------------
# 7) SEED Some Mock Orders
# ------------------------------------------------------------------------------
puts "Creating some sample Orders..."

orders_data = [
  # ...
]

regular_user = User.find_by(email: "user@example.com")

orders_data.each do |order_data|
  created_at_time = Time.zone.parse(order_data[:createdAt]) rescue Time.current
  pickup_time     = Time.zone.parse(order_data[:estimatedPickupTime]) rescue (created_at_time + 30.minutes)

  if Order.exists?(total: order_data[:total], created_at: created_at_time)
    puts "Order with total=#{order_data[:total]} at #{created_at_time} already exists; skipping."
    next
  end

  new_order = Order.create!(
    restaurant:            restaurant,
    user:                  regular_user,
    items:                 order_data[:items],
    status:                order_data[:status],
    total:                 order_data[:total],
    estimated_pickup_time: pickup_time
  )

  new_order.update_column(:created_at, created_at_time)

  puts "Created Order: #{new_order.id}, status=#{new_order.status}, total=#{new_order.total}"
end

puts "Done seeding sample Orders!"

puts "== Seeding complete! =="
