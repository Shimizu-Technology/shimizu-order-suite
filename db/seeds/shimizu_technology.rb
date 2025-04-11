# db/seeds/shimizu_technology.rb
# Seed data for Shimizu Technology restaurant

# Skip if Shimizu Technology already exists
unless Restaurant.exists?(name: "Shimizu Technology")
  puts "== Creating Shimizu Technology restaurant =="

  # ------------------------------------------------------------------------------
  # 1) RESTAURANT
  # ------------------------------------------------------------------------------
  restaurant = Restaurant.create!(
    name: "Shimizu Technology",
    address: "123 Tech Way, Silicon Valley, CA",
    phone_number: "+14155551234",
    time_slot_interval: 30,
    time_zone: "America/Los_Angeles",
    default_reservation_length: 90,
    layout_type: "seat-based",
    admin_settings: {
      "require_deposit" => false,
      "deposit_amount" => 0,
      "notification_channels" => {
        "orders" => {
          "email" => true,
          "sms" => false,
          "pushover" => false,
          "web_push" => false
        }
      },
      "payment_gateway" => {
        "test_mode" => true
      }
    },
    allowed_origins: [
      "http://localhost:5175",
      "https://shimizu-order-suite.netlify.app/"
    ]
  )

  puts "Created Restaurant: #{restaurant.name}"
  puts "   Address:  #{restaurant.address}"
  puts "   Phone:    #{restaurant.phone_number}"
  puts "   time_slot_interval: #{restaurant.time_slot_interval} mins"
  puts "   time_zone: #{restaurant.time_zone}"
  puts "   default_reservation_length: #{restaurant.default_reservation_length}"
  puts "   admin_settings: #{restaurant.admin_settings.inspect}"

  # ------------------------------------------------------------------------------
  # 1B) SEED OPERATING HOURS
  # ------------------------------------------------------------------------------
  oh_data = [
    { day_of_week: 0, open_time: "10:00:00", close_time: "20:00:00", closed: false }, # Sun
    { day_of_week: 1, open_time: "09:00:00", close_time: "21:00:00", closed: false }, # Mon
    { day_of_week: 2, open_time: "09:00:00", close_time: "21:00:00", closed: false }, # Tue
    { day_of_week: 3, open_time: "09:00:00", close_time: "21:00:00", closed: false }, # Wed
    { day_of_week: 4, open_time: "09:00:00", close_time: "21:00:00", closed: false }, # Thu
    { day_of_week: 5, open_time: "09:00:00", close_time: "22:00:00", closed: false }, # Fri
    { day_of_week: 6, open_time: "10:00:00", close_time: "22:00:00", closed: false }  # Sat
  ]

  oh_data.each do |row|
    OperatingHour.create!(
      restaurant_id: restaurant.id,
      day_of_week: row[:day_of_week],
      open_time: row[:open_time],
      close_time: row[:close_time],
      closed: row[:closed]
    )
  end

  puts "Created operating hours for restaurant"

  # ------------------------------------------------------------------------------
  # 2) USERS
  # ------------------------------------------------------------------------------
  admin = User.create!(
    email: "admin@shimizutechnology.com",
    password: "password123",
    password_confirmation: "password123",
    role: "admin",
    restaurant_id: restaurant.id,
    first_name: "Admin",
    last_name: "User"
  )

  puts "Created admin user: #{admin.email}"

  # ------------------------------------------------------------------------------
  # 3) MENU
  # ------------------------------------------------------------------------------
  main_menu = Menu.create!(
    name: "Main Menu",
    restaurant_id: restaurant.id
  )

  # Create a category for the menu
  category = Category.create!(
    name: "All In One",
    position: 0,
    description: "",
    menu_id: main_menu.id
  )

  # Create a sample menu item for Shimizu Technology
  menu_item = MenuItem.create!(
    menu_id: main_menu.id,
    name: "Order Suite",
    description: "Offer a branded online ordering portal to reduce phone traffic and errors—fully set up for you. Manage all orders, online and in-person, from one central system, with table-side ordering coming soon. Access powerful analytics (coming soon) to track sales, menu performance, and customer behavior across locations. Enhance service with integrated tools for VIP programs, merchandise, discounts, and house accounts.",
    price: 0,
    # Note: category field is deprecated, using join table instead
    category: nil,
    available: true,
    featured: true,
    stock_status: "in_stock"
  )

  # Associate the menu item with the category using the join table
  MenuItemCategory.create!(
    menu_item_id: menu_item.id,
    category_id: category.id
  )

  puts "Created main menu with sample item and category"
end
