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
  u.role       = "customer"   # or 'staff'
  u.restaurant_id = restaurant.id
end
puts "Created Regular User: #{regular_user.email} / password"

# ------------------------------------------------------------------------------
# 3) LAYOUT / SEAT SECTIONS / SEATS
# ------------------------------------------------------------------------------
main_layout = Layout.find_or_create_by!(
  name: "Main Layout",
  restaurant_id: restaurant.id
)

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

menu_items_data = [
  # APPETIZERS
  {
    id: 'tinkak-attach-gyoza',
    name: 'Tinkak-Attach Gyoza (6 pcs)',
    description: '(6 pieces) A familiar local dish with seasoned beef and vegetables, steamed and fried with our denanche finadene.',
    price: 13.95,
    category: 'appetizers',
    image: 'src/assets/Tinak-Attack-Gyoza.jpeg'
  },
  {
    id: 'omg-lumpia',
    name: 'O.M.G. (Oh My Gollai) Lumpia (6 pcs)',
    description: '(6 pieces) The wholesome local style spinach and cream cheese side dish wrapped as a spring roll and fried into a savory crisp. Served with our denanche finadene.',
    price: 11.95,
    category: 'appetizers',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'spicy-wings',
    name: 'Spicy Wings',
    description: 'Seasoned fried chicken wings, served along side our house blend spices and our homemade denanche ranch.',
    price: 13.95,
    category: 'appetizers',
    image: 'src/assets/Spicy-Wings.webp'
  },
  {
    id: 'garlic-fries',
    name: 'Garlic Fries',
    description: '',
    price: 8.95,
    category: 'appetizers',
    image: 'src/assets/Garlic-Fries.webp'
  },
  {
    id: 'french-fries',
    name: 'French Fries',
    description: '',
    price: 5.95,
    category: 'appetizers',
    image: 'src/assets/French-Fries.webp'
  },
  {
    id: 'cheezy-bugdilla',
    name: 'The-Cheesy-Pig-Quesadilla',
    description: 'Kalua pulled pork wrapped in a flour tortilla with lomi tomatoes and our special cheesy blend.',
    price: 13.95,
    category: 'appetizers',
    image: 'src/assets/The-Cheesy-Pig-Quesadilla.webp'
  },
  {
    id: 'onion-wrings',
    name: 'Onion Rings',
    description: '',
    price: 13.95,
    category: 'appetizers',
    image: 'src/assets/The-Cheesy-Pig-Quesadilla.webp'
  },

  # POKE
  {
    id: 'aloha-poke',
    name: 'Aloha Poke',
    description: 'A classic hawaiian style poke seasoned with hawaiian salt, tossed with onions, green onions, soy sauce, sesame oil, seasme seeds, inamona**, and limu**.',
    price: 16.95,
    category: 'poke',
    image: 'src/assets/Aloha-Poke.webp'
  },
  {
    id: 'spizy-tuna-poke',
    name: 'Spizy Tuna Poke',
    description: 'Tuna poke tossed with our homemade spicy mayo and tobiko.',
    price: 17.95,
    category: 'poke',
    image: 'src/assets/Spizy-Tuna-Poke.webp'
  },
  {
    id: 'tofu-poke',
    name: 'Tofu Poke',
    description: 'Cubed tofu, fried and marinated in our homemade teriyaki sauce, tossed with avocados**, cucumbers, tomatoes, onions, green onions.',
    price: 15.95,
    category: 'poke',
    image: 'src/assets/Tofu-Poke.webp'
  },
  {
    id: 'shoyu-poke',
    name: 'Shoyu Poke',
    description: 'Sweetend poke glazed in our homemade soysauce.',
    price: 15.95,
    category: 'poke',
    image: 'src/assets/Shoyu-Poke.webp'
  },
  {
    id: 'cali-poke',
    name: 'Cali Poke',
    description: 'A california roll in a bowl filled with ahi poke, crab, avocados**, and cucumbers tossed with our homemade creamy sauce.',
    price: 16.95,
    category: 'poke',
    image: 'src/assets/Cali-Poke.webp'
  },
  {
    id: 'pika-poke',
    name: 'Pika Poke',
    description: 'Seasoned ahi poke tossed in our homemade denanche sauce.',
    price: 15.95,
    category: 'poke',
    image: 'src/assets/Pika-Poke.webp'
  },
  {
    id: 'kelaguen-poke',
    name: 'Kelaguen Poke',
    description: 'Ahi poke tossed with coconut milk, lemon powder, tomatoes, red onions, green bell peppers, and cucumbers.',
    price: 16.95,
    category: 'poke',
    image: 'src/assets/Kelaguen-Poke.webp'
  },

  # BURGERS
  {
    id: 'hafaloha-burger',
    name: 'Hafaloha Burger',
    description: 'Signature burger with grilled pineapple & teriyaki glaze',
    price: 13.95,
    category: 'burgers',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'big-cheeseburger',
    name: "Da' Big Cheeseburger",
    description: 'Double patty with three types of cheese',
    price: 15.95,
    category: 'burgers',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'shroom-burger',
    name: 'Shroom Burger',
    description: 'Portobello mushroom & Swiss cheese',
    price: 13.95,
    category: 'burgers',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'blue-cheese-bacon-burger',
    name: 'Blue Cheese Bacon Burger',
    description: 'Rich blue cheese & crispy bacon',
    price: 17.95,
    category: 'burgers',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'ahi-burger',
    name: 'Ahi Burger',
    description: 'Seared ahi tuna patty with island sauce',
    price: 14.95,
    category: 'burgers',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'tori-chicken-burger',
    name: 'Tori Chicken Burger',
    description: 'Grilled chicken with island spices',
    price: 15.95,
    category: 'burgers',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'pepper-pineapple-burger',
    name: 'Pepper Pineapple Burger',
    description: 'Pepper-crusted patty with sweet pineapple',
    price: 16.95,
    category: 'burgers',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'torresueno-burger',
    name: 'Torresueno Burger',
    description: 'Ultimate burger loaded with special toppings',
    price: 18.95,
    category: 'burgers',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },

  # DESSERTS
  # Shave Ice
  {
    id: 'shave-ice-diki',
    name: 'Shave Ice (Diki)',
    description: 'Smaller portion of classic shave ice (up to 3 flavors)',
    price: 4.50,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'shave-ice-regular',
    name: 'Shave Ice (Regular)',
    description: 'Regular size shave ice (up to 3 flavors)',
    price: 7.50,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'shave-ice-kahuna',
    name: 'Shave Ice (Kahuna)',
    description: 'Large “Kahuna” size shave ice (up to 3 flavors)',
    price: 9.50,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  # Shave Ice Specials
  {
    id: 'shave-ice-special',
    name: 'Shave Ice Special',
    description: 'One size (includes vanilla soft-serve + 2 flavors)',
    price: 8.50,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'halo-halo',
    name: 'Halo Halo',
    description: 'Island-style halo halo with coconut jelly & ice cream',
    price: 9.00,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  # Ice Keki
  {
    id: 'ice-keki-single',
    name: 'Ice Keki (Single)',
    description: 'Japanese-inspired ice cream treat (single)',
    price: 3.20,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'ice-keki-case',
    name: 'Ice Keki (Case of 12)',
    description: 'Box of 12 ice keki—save $10 overall',
    price: 30.00,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  # Build-a-Bowl
  {
    id: 'build-a-bowl',
    name: 'Build-a-Bowl',
    description: 'Custom acai bowl—pick your fruit, granola, and honey drizzle',
    price: 9.25,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  # Soft-Serve
  {
    id: 'soft-serve',
    name: 'Soft-Serve',
    description: 'Creamy soft-serve ice cream (one size)',
    price: 6.25,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'soft-serve-special',
    name: 'Soft-Serve Special',
    description: 'One size — loaded with toppings (e.g., fruity pebbles, drizzle)',
    price: 8.50,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  # Frozen Fruit Cakes
  {
    id: 'frozen-fruit-cake-8',
    name: 'Frozen Fruit Cake (8")',
    description: '8-inch frozen fruit cake with choice of crust & toppings',
    price: 28.00,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'frozen-fruit-cake-10',
    name: 'Frozen Fruit Cake (10")',
    description: '10-inch frozen fruit cake—serves a crowd',
    price: 45.00,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'frozen-fruit-cake-quarter',
    name: 'Frozen Fruit Cake (1/4 Cake)',
    description: 'Quarter-sheet frozen fruit cake',
    price: 58.00,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'frozen-fruit-cake-half',
    name: 'Frozen Fruit Cake (1/2 Cake)',
    description: 'Half-sheet frozen fruit cake',
    price: 69.00,
    category: 'desserts',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },

  # DRINKS
  {
    id: 'breeze',
    name: 'Breeze',
    description: 'Vanilla soft-serve + real fruit juice (one size)',
    price: 8.25,
    category: 'drinks',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'smoothies',
    name: 'Smoothies',
    description: 'One size (20 oz) made with real fruit & juice',
    price: 8.00,
    category: 'drinks',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  },
  {
    id: 'soda-pop',
    name: 'Soda Pop (20 oz)',
    description: 'Choice of flavors, 20 oz cup',
    price: 4.75,
    category: 'drinks',
    image: 'src/assets/O.M.G-(Oh-My-Gollai)-Lumpia.webp'
  }
]

puts "Creating Main Menu with categories & items..."

main_menu = Menu.find_or_create_by!(name: "Main Menu", restaurant_id: restaurant.id)
main_menu.update!(active: true)

menu_items_data.each do |item_data|
  MenuItem.find_or_create_by!(menu_id: main_menu.id, name: item_data[:name]) do |mi|
    # Typically you don’t store the same "id" as the primary key, but you could store
    # it in a separate column if needed. We'll ignore the 'id' from front-end data
    # or store it as a `slug` if you like.
    mi.description = item_data[:description]
    mi.price       = item_data[:price]
    mi.category    = item_data[:category]
    mi.image_url   = item_data[:image]
    mi.available   = true
  end
end

puts "Seeded #{MenuItem.count} menu items under '#{main_menu.name}'."

# ------------------------------------------------------------------------------
# 7) SEED Some Mock Orders
# ------------------------------------------------------------------------------
puts "Creating some sample Orders..."

orders_data = [
  {
    id: 'ORD-001',
    user_id: 'user1', # We'll ignore this and attach to our "regular_user" below
    items: [
      {
        id: 'aloha-poke',
        name: 'Aloha Poke',
        quantity: 2,
        price: 15.99,
        customizations: {
          'Base' => ['Brown Rice'],
          'Add-ons' => ['Avocado', 'Masago']
        }
      },
      {
        id: 'tropical-smoothie',
        name: 'Tropical Smoothie',
        quantity: 1,
        price: 7.99,
        customizations: {
          'Base' => ['Mango'],
          'Add-ins' => ['Protein']
        }
      }
    ],
    status: 'completed',
    total: 39.97,
    createdAt: '2024-03-14T10:30:00Z',
    estimatedPickupTime: '2024-03-14T11:00:00Z'
  },
  {
    id: 'ORD-002',
    user_id: 'user1',
    items: [
      {
        id: 'hafaloha-burger',
        name: 'Hafaloha Burger',
        quantity: 1,
        price: 13.99,
        customizations: {
          'Temperature' => ['Medium'],
          'Add-ons'     => ['Bacon', 'Avocado']
        }
      },
      {
        id: 'shave-ice',
        name: 'Island Shave Ice',
        quantity: 2,
        price: 6.99,
        customizations: {
          'Flavors' => ['Mango', 'Lychee'],
          'Toppings'=> ['Mochi', 'Condensed Milk']
        }
      }
    ],
    status: 'completed',
    total: 27.97,
    createdAt: '2024-03-13T15:45:00Z',
    estimatedPickupTime: '2024-03-13T16:15:00Z'
  },
  {
    id: 'ORD-003',
    user_id: 'user1',
    items: [
      {
        id: 'spicy-wings',
        name: 'Spicy Wings',
        quantity: 2,
        price: 12.99,
        customizations: {
          'Sauce' => ['Buffalo']
        }
      },
      {
        id: 'soda-pop',
        name: 'Island Soda Pop',
        quantity: 2,
        price: 2.99,
        customizations: {
          'Flavor' => ['Cola'],
          'Size'   => ['Large']
        }
      }
    ],
    status: 'preparing',
    total: 31.96,
    createdAt: '2024-03-15T12:00:00Z',
    estimatedPickupTime: '2024-03-15T12:30:00Z',
    specialInstructions: 'Extra napkins please'
  }
]

regular_user = User.find_by(email: "user@example.com")

orders_data.each do |order_data|
  # Convert the mock "createdAt" string to a Ruby Time
  created_at_time = Time.zone.parse(order_data[:createdAt]) rescue Time.current
  pickup_time = Time.zone.parse(order_data[:estimatedPickupTime]) rescue (created_at_time + 30.minutes)

  # If re-running seeds, you might create duplicates. If you want a simple guard:
  if Order.exists?(total: order_data[:total], created_at: created_at_time)
    puts "Order with total=#{order_data[:total]} at created_at=#{created_at_time} already exists; skipping."
    next
  end

  new_order = Order.create!(
    restaurant: restaurant,
    user:       regular_user,    # or nil if guest
    items:      order_data[:items],  # JSONB
    status:     order_data[:status],
    total:      order_data[:total],
    special_instructions: order_data[:specialInstructions],
    estimated_pickup_time: pickup_time
    # created_at & updated_at are handled by AR normally
  )

  # If you really want to preserve the "createdAt" from mock data in DB:
  new_order.update_column(:created_at, created_at_time)

  puts "Created Order: #{new_order.id}, status=#{new_order.status}, total=#{new_order.total}"
end

puts "Done seeding sample Orders!"

puts "== Seeding complete! =="
