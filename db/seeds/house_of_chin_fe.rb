# db/seeds/house_of_chin_fe.rb
# Seed data for House of Chin Fe restaurant

unless Restaurant.exists?(name: "House of Chin Fe")
  puts "== Creating House of Chin Fe restaurant =="

  restaurant = Restaurant.create!(
    name: "House of Chin Fe",
    address: "620 N Marine Corps Dr, Hagåtña, 96910, Guam",
    phone_number: "+1 671-472-6135",
    time_slot_interval: 30,
    time_zone: "Pacific/Guam",
    default_reservation_length: 60,
    facebook_url: "https://www.facebook.com/thenewhouseofchinfeguam/",
    instagram_url: "https://www.instagram.com/houseofchinfe/",
    admin_settings: {
      "require_deposit" => false,
      "deposit_amount" => 0,
      "notification_channels" => {
        "orders" => {
          "email" => true,
          "sms" => true,
          "pushover" => false,
          "web_push" => false
        }
      },
      "payment_gateway" => {
        "test_mode" => true
      },
      "email_header_color" => "#E42423"
    },
    allowed_origins: [
      "http://localhost:5176"
    ]
  )

  puts "Created Restaurant: #{restaurant.name}"

  # Seed operating hours (6:30am - 9:00pm daily)
  oh_data = (0..6).map do |dow|
    { day_of_week: dow, open_time: "06:30:00", close_time: "21:00:00", closed: false }
  end

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

  # Create admin user (update credentials as needed)
  admin = User.create!(
    email: "admin@houseofchinfe.com",
    password: "password123",
    password_confirmation: "password123",
    role: "admin",
    restaurant_id: restaurant.id,
    first_name: "Admin",
    last_name: "User"
  )

  puts "Created admin user: #{admin.email}"
end
