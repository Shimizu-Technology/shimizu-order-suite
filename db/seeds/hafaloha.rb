# db/seeds/hafaloha.rb
# Seed file for Hafaloha restaurant

# Skip if Hafaloha already exists
unless Restaurant.exists?(name: "Hafaloha")
  puts "== Creating Hafaloha restaurant =="

  # ------------------------------------------------------------------------------
  # 1) RESTAURANT
  # ------------------------------------------------------------------------------
  restaurant = Restaurant.create!(
    name: "Hafaloha",
    address: "955 Pale San Vitores Rd, Tamuning, Guam 96913",
    phone_number: "+16719893444",
    time_slot_interval: 30,
    time_zone: "Pacific/Guam",
    default_reservation_length: 60,
    layout_type: "seat-based",
    facebook_url: "https://www.facebook.com/HafalohaInc/",
    instagram_url: "https://www.instagram.com/hafaloha/",
    twitter_url: nil,
    admin_settings: {
      "pushover" => {
        "user_key" => "u75y2asuw5wk6vsbsueeam35obpwjp",
        "app_token" => "agps7bb3ikj9g1f9gr1jybqwa2925u",
        "group_key" => "g5w7zf45hg1dmx4dyjmzduxvp1esf9"
      },
      "web_push" => {
        "vapid_public_key" => "BN70tb6Q7DpgSx2kNvseGfZa_-wqTm0JE6y4--kTT24uzLF-BpO1cL8S71YE5YDyNLAvTczWpPNusoA684ze0V0=",
        "vapid_private_key" => "qST2OFRIwzbuKcH2y6f7Vf2dhtSfeetF7cnMuZbLmAE="
      },
      "sms_sender_id" => "6716877162",
      "deposit_amount" => 0,
      "hero_image_url" => "https://hafaloha.s3.ap-southeast-2.amazonaws.com/hero_1_1742777620.webp",
      "payment_gateway" => {
        "client_id" => "AQKVPV4kvmmOQVy_4Ypsrp6MAVgKIEhbJWQjiVqVLlLMQQ8FeheMhAApG-cWsBbxoCdHZhiK0IsZaQSf",
        "test_mode" => true,
        "environment" => "sandbox",
        "payment_processor" => "stripe",
        "webhook_secret" => "whsec_qrbMPAqebzECBXmTl7xd1NfEr4oAOOgL",
        "publishable_key" => "pk_live_51R3q0bAl8GLLNpHbC1ffajndnqbPxZ7flYIPmwherMVrbUagJm72wT4bLEcu4zDC6Z6FPnUiEF0lQSmCH0BaTtIE00PiqRmRSM",
        "paypal_webhook_id" => "7EH30924FX663913D",
        "paypal_webhook_secret" => ""
      },
      "require_deposit" => false,
      "spinner_image_url" => "https://hafaloha.s3.ap-southeast-2.amazonaws.com/spinner_1_1742509156.png",
      "whatsapp_group_id" => "120363398524235626@g.us",
      "email_header_color" => "#D4AF37",
      "notification_channels" => {
        "orders" => {
          "sms" => true,
          "email" => true,
          "pushover" => false,
          "web_push" => true
        }
      }
    },
    allowed_origins: [
      "http://localhost:5173",
      "http://localhost:5174",
      "https://hafaloha-orders.com"
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
    { day_of_week: 0, open_time: "11:00:00", close_time: "21:00:00", closed: false }, # Sun
    { day_of_week: 1, open_time: nil,        close_time: nil,        closed: true },  # Mon
    { day_of_week: 2, open_time: "11:00:00", close_time: "21:00:00", closed: false }, # Tue
    { day_of_week: 3, open_time: "11:00:00", close_time: "21:00:00", closed: false }, # Wed
    { day_of_week: 4, open_time: "11:00:00", close_time: "21:00:00", closed: false }, # Thu
    { day_of_week: 5, open_time: "11:00:00", close_time: "22:00:00", closed: false }, # Fri
    { day_of_week: 6, open_time: "11:00:00", close_time: "22:00:00", closed: false }  # Sat
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
  # Create admin users based on current database
  admin1 = User.create!(
    email: "lmshimizu@gmail.com",
    password: "password123",
    password_confirmation: "password123",
    role: "admin",
    restaurant_id: restaurant.id,
    first_name: "Leon",
    last_name: "Shimizu",
    phone: "+16714830219"
  )

  admin2 = User.create!(
    email: "sales@hafaloha.com",
    password: "password123",
    password_confirmation: "password123",
    role: "admin",
    restaurant_id: restaurant.id,
    first_name: "Shop",
    last_name: "Orders",
    phone: "+16719893444"
  )

  admin3 = User.create!(
    email: "tara@hafaloha.com",
    password: "password123",
    password_confirmation: "password123",
    role: "admin",
    restaurant_id: restaurant.id,
    first_name: "Tara",
    last_name: "Kaae",
    phone: "+16716877322"
  )
  
  admin4 = User.create!(
    email: "tasirose@hafaloha.com",
    password: "password123",
    password_confirmation: "password123",
    role: "admin",
    restaurant_id: restaurant.id,
    first_name: "Tasi-Rose",
    last_name: "Camacho",
    phone: "+16716862506"
  )
  
  admin5 = User.create!(
    email: "rheada@hafaloha.com",
    password: "password123",
    password_confirmation: "password123",
    role: "admin",
    restaurant_id: restaurant.id,
    first_name: "Rhea'da",
    last_name: "Macaraeg",
    phone: "+18085542317"
  )

  puts "Created admin users"

  # ------------------------------------------------------------------------------
  # 3) MENU
  # ------------------------------------------------------------------------------
  main_menu = Menu.create!(
    name: "Main Menu",
    restaurant_id: restaurant.id,
    active: true
  )

  puts "Created main menu"

  # ------------------------------------------------------------------------------
  # 4) CATEGORIES
  # ------------------------------------------------------------------------------
  # Create categories based on current database
  desserts_category = Category.create!(
    name: "Desserts",
    position: 0,
    menu_id: main_menu.id
  )

  drinks_category = Category.create!(
    name: "Drinks",
    position: 0,
    menu_id: main_menu.id
  )

  plates_category = Category.create!(
    name: "Plates",
    position: 0,
    menu_id: main_menu.id
  )

  retail_category = Category.create!(
    name: "Retail",
    position: 0,
    description: "",
    menu_id: main_menu.id
  )

  appetizers_category = Category.create!(
    name: "Appetizers",
    position: 0,
    menu_id: main_menu.id
  )

  bowls_category = Category.create!(
    name: "Bowls",
    position: 0,
    description: "- Consuming raw and undercooked meats, poultry, seafood, shellfish, or eggs may increase your risk of foodborne illness",
    menu_id: main_menu.id
  )

  burgers_category = Category.create!(
    name: "Burgers",
    position: 0,
    description: "All handcrafted burgers are 1/2 pound USDA choice beef patties",
    menu_id: main_menu.id
  )

  platters_category = Category.create!(
    name: "Platters",
    position: 0,
    description: "For Platter orders, will need to be ordered 24 hours in advance",
    menu_id: main_menu.id
  )

  puts "Created categories"

  # ------------------------------------------------------------------------------
  # 5) MENU ITEMS
  # ------------------------------------------------------------------------------
  # Create sample menu items for each category with their associations
  
  # Desserts
  build_a_bowl = MenuItem.create!(
    menu_id: main_menu.id,
    name: "Build-A-Bowl",
    description: "Custom fruit bowl—pick your base and add as many toppings as you'd like!",
    price: 8.0,
    category: nil,
    available: true,
    featured: true,
    image_url: "https://hafaloha.s3.ap-southeast-2.amazonaws.com/menu_item_26_1739747052.webp"
  )
  
  MenuItemCategory.create!(
    menu_item_id: build_a_bowl.id,
    category_id: desserts_category.id
  )

  shave_ice = MenuItem.create!(
    menu_id: main_menu.id,
    name: "Shave Ice",
    description: "Customize your shave ice YOUR way—mix up to three flavors!",
    price: 6.5,
    category: nil,
    available: true,
    featured: false,
    image_url: "https://hafaloha.s3.ap-southeast-2.amazonaws.com/menu_item_21_1739747735.webp"
  )
  
  MenuItemCategory.create!(
    menu_item_id: shave_ice.id,
    category_id: desserts_category.id
  )

  # Drinks
  smoothies = MenuItem.create!(
    menu_id: main_menu.id,
    name: "Smoothies (20 oz.)",
    description: "Smoothies made real fresh & with REAL fruit—One size only",
    price: 8.25,
    category: nil,
    available: true,
    featured: false,
    image_url: "https://hafaloha.s3.ap-southeast-2.amazonaws.com/menu_item_34_1742862792.jpg"
  )
  
  MenuItemCategory.create!(
    menu_item_id: smoothies.id,
    category_id: drinks_category.id
  )

  # Plates
  hawaiian_plate = MenuItem.create!(
    menu_id: main_menu.id,
    name: "Hawaiian Plate",
    description: "Your Hawaiian favorites all wrapped into one plate. Includes kalua pork, teriyaki chicken, and macaroni salad, all on a bed of rice.",
    price: 25.95,
    category: nil,
    available: true,
    featured: false,
    image_url: "https://hafaloha.s3.ap-southeast-2.amazonaws.com/menu_item_74_1741976564.jpg"
  )
  
  MenuItemCategory.create!(
    menu_item_id: hawaiian_plate.id,
    category_id: plates_category.id
  )

  # Appetizers
  cheesy_pig = MenuItem.create!(
    menu_id: main_menu.id,
    name: "The Cheesy Pig Quesadilla",
    description: "Kalua pulled pork wrapped in a flour tortilla with melted cheese and topped with our homemade spicy mayo sauce.",
    price: 13.95,
    category: nil,
    available: true,
    featured: false,
    image_url: "https://hafaloha.s3.ap-southeast-2.amazonaws.com/menu_item_6_1739747976.webp"
  )
  
  MenuItemCategory.create!(
    menu_item_id: cheesy_pig.id,
    category_id: appetizers_category.id
  )

  # Bowls
  cali_poke = MenuItem.create!(
    menu_id: main_menu.id,
    name: "Cali Poke",
    description: "A california roll in a bowl filled with ahi poke, crab meat, avocado, cucumber, and tobiko, all on a bed of rice.",
    price: 16.95,
    category: nil,
    available: true,
    featured: false,
    image_url: "https://hafaloha.s3.ap-southeast-2.amazonaws.com/menu_item_12_1741982347.jpg"
  )
  
  MenuItemCategory.create!(
    menu_item_id: cali_poke.id,
    category_id: bowls_category.id
  )

  # Burgers
  hafaloha_burger = MenuItem.create!(
    menu_id: main_menu.id,
    name: "Håfaloha Burger",
    description: "Hawaiian Sweet Roll bun stacked on our well-seasoned beef patty, topped with lettuce, tomato, onion, and our homemade burger sauce.",
    price: 13.95,
    category: nil,
    available: true,
    featured: false,
    image_url: "https://hafaloha.s3.ap-southeast-2.amazonaws.com/menu_item_15_1741978996.jpg"
  )
  
  MenuItemCategory.create!(
    menu_item_id: hafaloha_burger.id,
    category_id: burgers_category.id
  )

  # Platters
  chicken_platter = MenuItem.create!(
    menu_id: main_menu.id,
    name: "Mochiko Chicken Platter",
    price: 65.0,
    category: nil,
    available: true,
    featured: false,
    image_url: "https://hafaloha.s3.ap-southeast-2.amazonaws.com/menu_item_248_1743192972.png"
  )
  
  MenuItemCategory.create!(
    menu_item_id: chicken_platter.id,
    category_id: platters_category.id
  )

  puts "Created menu items with category associations"

  # ------------------------------------------------------------------------------
  # 5B) OPTION GROUPS AND OPTIONS
  # ------------------------------------------------------------------------------
  # Create option groups and options for menu items
  
  # Shave Ice Options
  flavor_group = OptionGroup.create!(
    name: "Flavors",
    description: "Choose up to 3 flavors",
    restaurant_id: restaurant.id,
    min_selections: 1,
    max_selections: 3,
    position: 0
  )
  
  ["Blue Hawaii", "Cherry", "Coconut", "Grape", "Green Apple", "Guava", "Lemon", "Lilikoi", "Lime", "Mango", 
   "Orange", "Pineapple", "Strawberry", "Vanilla", "Watermelon"].each_with_index do |flavor, index|
    Option.create!(
      name: flavor,
      price: 0.0,
      position: index,
      option_group_id: flavor_group.id
    )
  end
  
  # Associate option group with menu item
  MenuItemOptionGroup.create!(
    menu_item_id: shave_ice.id,
    option_group_id: flavor_group.id,
    required: true
  )
  
  # Smoothie Options
  smoothie_flavor_group = OptionGroup.create!(
    name: "Smoothie Flavors",
    description: "Choose your smoothie flavor",
    restaurant_id: restaurant.id,
    min_selections: 1,
    max_selections: 1,
    position: 0
  )
  
  ["Strawberry", "Mango", "Pineapple", "Mixed Berry", "Banana"].each_with_index do |flavor, index|
    Option.create!(
      name: flavor,
      price: 0.0,
      position: index,
      option_group_id: smoothie_flavor_group.id
    )
  end
  
  # Associate option group with menu item
  MenuItemOptionGroup.create!(
    menu_item_id: smoothies.id,
    option_group_id: smoothie_flavor_group.id,
    required: true
  )
  
  # Burger Options
  burger_addon_group = OptionGroup.create!(
    name: "Burger Add-ons",
    description: "Customize your burger",
    restaurant_id: restaurant.id,
    min_selections: 0,
    max_selections: 5,
    position: 0
  )
  
  [
    {name: "Extra Patty", price: 3.95},
    {name: "Bacon", price: 1.95},
    {name: "Cheese", price: 0.95},
    {name: "Avocado", price: 1.50},
    {name: "Fried Egg", price: 1.25}
  ].each_with_index do |addon, index|
    Option.create!(
      name: addon[:name],
      price: addon[:price],
      position: index,
      option_group_id: burger_addon_group.id
    )
  end
  
  # Associate option group with menu item
  MenuItemOptionGroup.create!(
    menu_item_id: hafaloha_burger.id,
    option_group_id: burger_addon_group.id,
    required: false
  )
  
  # Poke Bowl Protein Options
  protein_group = OptionGroup.create!(
    name: "Protein",
    description: "Choose your protein",
    restaurant_id: restaurant.id,
    min_selections: 1,
    max_selections: 1,
    position: 0
  )
  
  [
    {name: "Ahi Poke", price: 0.0},
    {name: "Salmon Poke", price: 0.0},
    {name: "Cooked Shrimp", price: 0.0},
    {name: "Tofu", price: -2.0}
  ].each_with_index do |protein, index|
    Option.create!(
      name: protein[:name],
      price: protein[:price],
      position: index,
      option_group_id: protein_group.id
    )
  end
  
  # Associate option group with menu item
  MenuItemOptionGroup.create!(
    menu_item_id: cali_poke.id,
    option_group_id: protein_group.id,
    required: true
  )

  puts "Created option groups and options"

  # ------------------------------------------------------------------------------
  # 6) LAYOUT
  # ------------------------------------------------------------------------------
  layout = Layout.create!(
    name: "Main Layout",
    restaurant_id: restaurant.id,
    active: true,
    default: true
  )

  # Create seat sections
  inside_section = SeatSection.create!(
    layout_id: layout.id,
    name: "Inside",
    position: 0,
    color: "#4CAF50",
    capacity: 24
  )

  outside_section = SeatSection.create!(
    layout_id: layout.id,
    name: "Outside",
    position: 1,
    color: "#2196F3",
    capacity: 16
  )

  bar_section = SeatSection.create!(
    layout_id: layout.id,
    name: "Bar",
    position: 2,
    color: "#FF9800",
    capacity: 8
  )

  private_section = SeatSection.create!(
    layout_id: layout.id,
    name: "Private Room",
    position: 3,
    color: "#9C27B0",
    capacity: 12
  )

  # Create seats for each section
  # Inside section seats
  (1..6).each do |i|
    Seat.create!(
      seat_section_id: inside_section.id,
      name: "Table #{i}",
      capacity: 4,
      x_position: 100 + (i-1)*120,
      y_position: 100,
      shape: "circle",
      width: 80,
      height: 80
    )
  }

  # Outside section seats
  (1..4).each do |i|
    Seat.create!(
      seat_section_id: outside_section.id,
      name: "Patio #{i}",
      capacity: 4,
      x_position: 100 + (i-1)*120,
      y_position: 250,
      shape: "circle",
      width: 80,
      height: 80
    )
  }

  # Bar seats
  (1..8).each do |i|
    Seat.create!(
      seat_section_id: bar_section.id,
      name: "Bar #{i}",
      capacity: 1,
      x_position: 50 + (i-1)*50,
      y_position: 400,
      shape: "square",
      width: 40,
      height: 40
    )
  }

  # Private room seats
  (1..3).each do |i|
    Seat.create!(
      seat_section_id: private_section.id,
      name: "Private #{i}",
      capacity: 4,
      x_position: 100 + (i-1)*150,
      y_position: 550,
      shape: "rectangle",
      width: 100,
      height: 60
    )
  }

  puts "Created layout, seat sections, and seats"

  # ------------------------------------------------------------------------------
  # 7) FEATURE FLAGS
  # ------------------------------------------------------------------------------
  # Create feature flags for the restaurant
  [
    {key: "online_ordering", enabled: true, description: "Enable online ordering functionality"},
    {key: "reservations", enabled: true, description: "Enable reservations functionality"},
    {key: "merchandise", enabled: true, description: "Enable merchandise sales"},
    {key: "loyalty_program", enabled: false, description: "Enable loyalty program functionality"},
    {key: "gift_cards", enabled: true, description: "Enable gift card sales"},
    {key: "pickup_scheduling", enabled: true, description: "Enable pickup time scheduling"},
    {key: "delivery", enabled: false, description: "Enable delivery options"}
  ].each do |flag|
    FeatureFlag.create!(
      restaurant_id: restaurant.id,
      key: flag[:key],
      enabled: flag[:enabled],
      description: flag[:description]
    )
  end

  puts "Created feature flags"

  # ------------------------------------------------------------------------------
  # 8) MERCHANDISE COLLECTIONS
  # ------------------------------------------------------------------------------
  # Create merchandise collections
  apparel_collection = MerchandiseCollection.create!(
    name: "Apparel",
    description: "Hafaloha branded clothing and accessories",
    restaurant_id: restaurant.id,
    position: 0
  )

  gifts_collection = MerchandiseCollection.create!(
    name: "Gifts & Souvenirs",
    description: "Take a piece of Hafaloha home with you",
    restaurant_id: restaurant.id,
    position: 1
  )

  # Create merchandise items
  tshirt = MenuItem.create!(
    menu_id: main_menu.id,
    name: "Hafaloha T-Shirt",
    description: "100% cotton t-shirt with Hafaloha logo",
    price: 24.95,
    category: nil,
    available: true,
    featured: false,
    image_url: "https://hafaloha.s3.ap-southeast-2.amazonaws.com/merchandise_tshirt.jpg",
    is_merchandise: true
  )

  MenuItemCategory.create!(
    menu_item_id: tshirt.id,
    category_id: retail_category.id
  )

  MerchandiseItem.create!(
    menu_item_id: tshirt.id,
    merchandise_collection_id: apparel_collection.id
  )

  hat = MenuItem.create!(
    menu_id: main_menu.id,
    name: "Hafaloha Snapback Hat",
    description: "Adjustable snapback hat with embroidered Hafaloha logo",
    price: 29.95,
    category: nil,
    available: true,
    featured: false,
    image_url: "https://hafaloha.s3.ap-southeast-2.amazonaws.com/merchandise_hat.jpg",
    is_merchandise: true
  )

  MenuItemCategory.create!(
    menu_item_id: hat.id,
    category_id: retail_category.id
  )

  MerchandiseItem.create!(
    menu_item_id: hat.id,
    merchandise_collection_id: apparel_collection.id
  )

  mug = MenuItem.create!(
    menu_id: main_menu.id,
    name: "Hafaloha Coffee Mug",
    description: "Ceramic coffee mug with Hafaloha logo",
    price: 14.95,
    category: nil,
    available: true,
    featured: false,
    image_url: "https://hafaloha.s3.ap-southeast-2.amazonaws.com/merchandise_mug.jpg",
    is_merchandise: true
  )

  MenuItemCategory.create!(
    menu_item_id: mug.id,
    category_id: retail_category.id
  )

  MerchandiseItem.create!(
    menu_item_id: mug.id,
    merchandise_collection_id: gifts_collection.id
  )

  puts "Created merchandise collections and items"

  # ------------------------------------------------------------------------------
  # 9) AUDIT LOGS
  # ------------------------------------------------------------------------------
  # Create sample audit logs for the restaurant
  [
    {action: "restaurant.created", actor_id: admin1.id, actor_type: "User", target_id: restaurant.id, target_type: "Restaurant", changes: {name: [nil, "Hafaloha"], address: [nil, "955 Pale San Vitores Rd, Tamuning, Guam 96913"]}},
    {action: "menu.created", actor_id: admin1.id, actor_type: "User", target_id: main_menu.id, target_type: "Menu", changes: {name: [nil, "Main Menu"], active: [nil, true]}},
    {action: "user.created", actor_id: admin1.id, actor_type: "User", target_id: admin2.id, target_type: "User", changes: {email: [nil, "sales@hafaloha.com"], role: [nil, "admin"]}},
    {action: "menu_item.created", actor_id: admin2.id, actor_type: "User", target_id: build_a_bowl.id, target_type: "MenuItem", changes: {name: [nil, "Build-A-Bowl"], price: [nil, 8.0]}},
    {action: "layout.created", actor_id: admin3.id, actor_type: "User", target_id: layout.id, target_type: "Layout", changes: {name: [nil, "Main Layout"]}}
  ].each do |log|
    AuditLog.create!(
      restaurant_id: restaurant.id,
      action: log[:action],
      actor_id: log[:actor_id],
      actor_type: log[:actor_type],
      target_id: log[:target_id],
      target_type: log[:target_type],
      changes: log[:changes],
      created_at: rand(1..30).days.ago
    )
  end

  puts "Created sample audit logs"
end
