# house_of_chin_fe_production.rb
# A script to create a complete menu structure for House of Chin Fe in production
# This script handles proper tenant isolation and error handling

require 'logger'

# Initialize logger
log_file = File.open("#{Rails.root}/log/house_of_chin_fe_menu_setup_#{Time.now.strftime('%Y%m%d%H%M%S')}.log", 'w')
$logger = Logger.new(log_file)
$logger.level = Logger::INFO

# Also log to STDOUT
$console_logger = Logger.new(STDOUT)
$console_logger.level = Logger::INFO

def log(message, level = :info)
  $logger.send(level, message)
  $console_logger.send(level, message)
end

log "Starting House of Chin Fe menu setup script", :info
log "======================================", :info

# Set restaurant ID to 2 (House of Chin Fe)
restaurant_id = ENV['RESTAURANT_ID'] || "3"

begin
  # Find the restaurant
  restaurant = Restaurant.find(restaurant_id)
  log "Setting up menu for restaurant: #{restaurant.name} (ID: #{restaurant.id})", :info
  
  # Set the tenant context for proper isolation
  ActiveRecord::Base.current_restaurant = restaurant
  
  # Verify tenant context
  log "Tenant context set to restaurant ID: #{ActiveRecord::Base.current_restaurant&.id}", :info
  
  # Transaction to ensure all or nothing
  ActiveRecord::Base.transaction do
    # 1. Create a new menu
    log "Creating new menu...", :info
    # Generate a unique name with timestamp to avoid conflicts
    menu_name = "House of Chin Fe Menu #{Time.now.strftime('%Y%m%d_%H%M%S')}"
    
    main_menu = Menu.create!(
      restaurant_id: restaurant.id,
      name: menu_name,
      active: false # Set to false as requested
    )
    
    log "Created new menu: #{main_menu.name} (ID: #{main_menu.id})", :info
    
    # 2. Create categories
    log "Creating categories...", :info
    categories = {}
    
    # Define categories for House of Chin Fe
    # Breakfast Categories
    category_names = {
      breakfast_fried_rice: "FRIED RICE",
      build_your_own_omelet: "BUILD YOUR OWN OMELET",
      breakfast_classics: "BREAKFAST CLASSICS",
      from_the_griddle: "FROM THE GRIDDLE",
      breakfast_sandwiches: "SANDWICHES",
      breakfast_sides: "SIDES",
      
      # Lunch & Dinner Categories
      chin_fe_favorites: "CHIN FE FAVORITES",
      shrimp: "SHRIMP",
      beef: "BEEF",
      foo_young: "FOO YOUNG",
      chicken: "CHICKEN",
      pork: "PORK",
      pancit: "PANCIT",
      chinese_appetizers: "CHINESE APPETIZERS",
      soup: "SOUP",
      fish: "FISH",
      duck: "DUCK",
      crispy_noodles: "CRISPY NOODLES",
      fried_rice: "FRIED RICE",
      mixed_cuisine: "MIXED CUISINE",
      burgers_sandwiches: "BURGERS / SANDWICHES",
      steak_chops: "STEAK & CHOPS",
      filipino: "FILIPINO",
      japanese: "JAPANESE",
      korean: "KOREAN",
      italian: "ITALIAN",
      chamorro_appetizers: "CHAMORRO APPETIZERS",
      chamorro_entrees: "CHAMORRO ENTREES",
      local_favorites: "LOCAL FAVORITES",
      sides: "SIDES",
      desserts: "DESSERTS",
      beverages: "BEVERAGES",
      wines_glass: "WINES (GLASS)",
      wines_bottle: "WINES (BOTTLE)",
      imported_beers: "IMPORTED BEERS",
      domestic_beers: "DOMESTIC BEERS"
    }
    
    category_names.each do |key, name|
      categories[key] = Category.find_or_create_by!(
        menu_id: main_menu.id,
        name: name
      ) do |cat|
        # Any additional attributes can be set here
      end
      log "Created/found category: #{categories[key].name} (ID: #{categories[key].id})", :info
    end
    
    # Helper method to create a menu item and associate it with a category
    def create_menu_item(menu, category, name, description = nil, price = 0.0, is_available = true)
      # Check if the menu item already exists
      existing_item = MenuItem.find_by(menu_id: menu.id, name: name)
      
      if existing_item
        # Update the existing item
        existing_item.update!(
          description: description,
          price: price,
          available: is_available,
          image_url: "https://via.placeholder.com/300x200.png?text=#{name.gsub(' ', '+')}"
        )
        
        # Make sure it's associated with the category
        unless existing_item.categories.include?(category)
          MenuItemCategory.create!(menu_item_id: existing_item.id, category_id: category.id)
        end
        
        log "Updated menu item: #{existing_item.name} (ID: #{existing_item.id})", :info
        return existing_item
      else
        # Create a new item with category association
        MenuItem.transaction do
          # Build the menu item without saving yet
          item = MenuItem.new(
            menu_id: menu.id,
            name: name,
            description: description,
            price: price,
            available: is_available,
            image_url: "https://via.placeholder.com/300x200.png?text=#{name.gsub(' ', '+')}"
          )
          
          # Create the category association before saving
          item.categories << category
          
          # Now save the item with its association
          item.save!
          
          log "Created menu item: #{item.name} (ID: #{item.id})", :info
          return item
        end
      end
    end
    
    # 3. Create menu items for each category - starting with breakfast items
    log "Creating menu items...", :info
    
    # FRIED RICE items
    log "Creating fried rice breakfast items...", :info
    fried_rice_items = [
      { name: "Corned Beef Fried Rice", description: "With 2 Eggs cooked your way", price: 14.50 },
      { name: "Ham Fried Rice", description: "With 2 Eggs cooked your way", price: 14.50 },
      { name: "Bacon Fried Rice", description: "With 2 Eggs cooked your way", price: 13.50 },
      { name: "Spam Fried Rice", description: "With 2 Eggs cooked your way", price: 13.50 },
      { name: "Garlic Fried Rice", description: "With 2 Eggs cooked your way", price: 11.50 }
    ]
    
    fried_rice_items.each do |item|
      create_menu_item(main_menu, categories[:breakfast_fried_rice], item[:name], item[:description], item[:price])
    end
    
    # BUILD YOUR OWN OMELET items
    log "Creating build your own omelet items...", :info
    
    # Create the base omelet item
    build_your_own_omelet = create_menu_item(
      main_menu, 
      categories[:build_your_own_omelet], 
      "Plain Omelet", 
      "With 3 Eggs, Rice, Toast or English Muffin", 
      9.00
    )
    
    # Create option groups for the omelet
    protein_group = OptionGroup.find_or_create_by!(
      menu_item_id: build_your_own_omelet.id,
      name: "Protein Options"
    ) do |group|
      group.min_select = 0
      group.max_select = 4
      group.free_option_count = 0
    end
    
    veggie_group = OptionGroup.find_or_create_by!(
      menu_item_id: build_your_own_omelet.id,
      name: "Vegetable Options"
    ) do |group|
      group.min_select = 0
      group.max_select = 7
      group.free_option_count = 0
    end
    
    # Protein options
    protein_options = [
      { name: "Bacon", price: 2.00 },
      { name: "Spam", price: 2.00 },
      { name: "Corned Beef", price: 2.00 },
      { name: "Ham", price: 2.00 }
    ]
    
    protein_options.each do |option_data|
      Option.find_or_create_by!(
        option_group_id: protein_group.id,
        name: option_data[:name]
      ) do |option|
        option.additional_price = option_data[:price]
        option.is_available = true
      end
    end
    
    # Veggie options
    veggie_options = [
      { name: "Tomatoes", price: 1.50 },
      { name: "Onions", price: 1.50 },
      { name: "Green Onions", price: 1.50 },
      { name: "Mushrooms", price: 1.50 },
      { name: "Spinach", price: 1.50 },
      { name: "Eggplant", price: 1.50 },
      { name: "Cheese", price: 1.50 }
    ]
    
    veggie_options.each do |option_data|
      Option.find_or_create_by!(
        option_group_id: veggie_group.id,
        name: option_data[:name]
      ) do |option|
        option.additional_price = option_data[:price]
        option.is_available = true
      end
    end
    
    log "Created Build Your Own Omelet with option groups", :info
    
    # BREAKFAST CLASSICS
    log "Creating breakfast classics items...", :info
    breakfast_classics_items = [
      { name: "Portugal Sardines", description: "Garlic Fried Rice & 2 Eggs your way (Tomato Sauce, Olive Oil, Spiced-in Olive Oil)", price: 15.95 },
      { name: "Loco Moco", price: 15.95 },
      { name: "Fried Chicken and Waffles", price: 15.95 },
      { name: "Eggplant Omelet", description: "Choice of Meat, and Hash browns or Rice", price: 14.95 },
      { name: "Corned Beef Hash", description: "Rice & Eggs", price: 14.50 },
      { name: "2 Eggs your way", description: "Choice of Meat, Pancake, Hashbrowns or Rice, Toast or English Muffin", price: 13.95 },
      { name: "Egg Foo Young", description: "With Steamed Rice", price: 11.95 },
      { name: "Shrimp Foo Young", description: "With Steamed Rice", price: 14.95 }
    ]
    
    breakfast_classics_items.each do |item|
      create_menu_item(main_menu, categories[:breakfast_classics], item[:name], item[:description], item[:price])
    end
    
    # FROM THE GRIDDLE
    log "Creating from the griddle items...", :info
    griddle_items = [
      { name: "Pancakes", price: 9.50 },
      { name: "French Toast", price: 9.50 },
      { name: "Waffles", price: 9.50 },
      { name: "Pancakes with Meat", description: "With Bacon, Spam, Portuguese Sausage, Link Sausage, or Ham", price: 13.50 },
      { name: "French Toast with Meat", description: "With Bacon, Spam, Portuguese Sausage, Link Sausage, or Ham", price: 13.50 },
      { name: "Waffles with Meat", description: "With Bacon, Spam, Portuguese Sausage, Link Sausage, or Ham", price: 13.50 }
    ]
    
    griddle_items.each do |item|
      create_menu_item(main_menu, categories[:from_the_griddle], item[:name], item[:description], item[:price])
    end
    
    # BREAKFAST SANDWICHES
    log "Creating breakfast sandwich items...", :info
    breakfast_sandwich_items = [
      { name: "Ham, Egg & Cheese Sandwich", description: "Served with French Fries", price: 12.95 },
      { name: "Tuna Melt", description: "Served with French Fries", price: 12.95 },
      { name: "Grilled Ham & Cheese", description: "Served with French Fries", price: 11.95 },
      { name: "Grilled Cheese", description: "Served with French Fries. Upgrade to a Bagel as your choice of bread for $1.00 more!", price: 7.95 }
    ]
    
    breakfast_sandwich_items.each do |item|
      create_menu_item(main_menu, categories[:breakfast_sandwiches], item[:name], item[:description], item[:price])
    end
    
    # BREAKFAST SIDES
    log "Creating breakfast sides items...", :info
    breakfast_sides_items = [
      { name: "Oatmeal with Blueberries & Walnuts", price: 7.00 },
      { name: "Bacon", price: 5.25 },
      { name: "Ham", price: 5.25 },
      { name: "Sausage Links", price: 5.25 },
      { name: "Spam", price: 5.25 },
      { name: "Portuguese Sausage", price: 5.25 },
      { name: "Bagel with Cream Cheese", price: 3.75 },
      { name: "Hash browns", price: 3.50 },
      { name: "Toast", price: 2.50 },
      { name: "English Muffin", price: 2.50 },
      { name: "Eggs", price: 2.25 }
    ]
    
    breakfast_sides_items.each do |item|
      create_menu_item(main_menu, categories[:breakfast_sides], item[:name], item[:description], item[:price])
    end
    
    log "Breakfast menu items created successfully!", :info
    
    # Now adding lunch and dinner menu items
    log "Adding lunch and dinner menu items...", :info
    
    # CHIN FE FAVORITES
    log "Creating Chin Fe Favorites items...", :info
    chin_fe_favorites_items = [
      { name: "Chin Fe Chinese Dinner", description: "Three different Chin Fe Favorites served with two bowls of House Fried Rice. Serves 2.", price: 35.00 }
    ]
    
    chin_fe_favorites_items.each do |item|
      create_menu_item(main_menu, categories[:chin_fe_favorites], item[:name], item[:description], item[:price])
    end
    
    # SHRIMP
    log "Creating shrimp items...", :info
    shrimp_items = [
      { name: "Shrimp Chop Suey", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 14.50 },
      { name: "Shrimp Chow Mein", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 14.50 },
      { name: "Chili Garlic Shrimp", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 15.75 },
      { name: "Shrimp Broccoli", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 14.50 },
      { name: "Shrimp Mushroom", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 14.50 },
      { name: "Honey Walnut Shrimp", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 15.75 },
      { name: "Fried Shrimp", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 15.75 },
      { name: "Sweet and Sour Shrimp", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 15.75 }
    ]
    
    shrimp_items.each do |item|
      create_menu_item(main_menu, categories[:shrimp], item[:name], item[:description], item[:price])
    end
    
    # BEEF
    log "Creating beef items...", :info
    beef_items = [
      { name: "Beef Broccoli", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 14.50 },
      { name: "Beef Chop Suey", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 14.50 },
      { name: "Beef Chow Mein", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 14.50 }
    ]
    
    beef_items.each do |item|
      create_menu_item(main_menu, categories[:beef], item[:name], item[:description], item[:price])
    end
    
    # FOO YOUNG
    log "Creating foo young items...", :info
    foo_young_items = [
      { name: "Egg Foo Young", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 12.45 },
      { name: "Chicken Foo Young", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 13.95 },
      { name: "Pork Foo Young", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 13.95 },
      { name: "Shrimp Foo Young", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 14.95 }
    ]
    
    foo_young_items.each do |item|
      create_menu_item(main_menu, categories[:foo_young], item[:name], item[:description], item[:price])
    end
    
    # CHICKEN
    log "Creating chicken items...", :info
    chicken_items = [
      { name: "Chicken Chop Suey", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 13.95 },
      { name: "Chicken Chow Mein", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 13.95 },
      { name: "Chicken Broccoli", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 13.95 },
      { name: "Orange Chicken", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 13.95 },
      { name: "Soy Sauce Chicken", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 13.95 },
      { name: "Spicy Chicken Ginger", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 13.95 }
    ]
    
    chicken_items.each do |item|
      create_menu_item(main_menu, categories[:chicken], item[:name], item[:description], item[:price])
    end
    
    # PORK
    log "Creating pork items...", :info
    pork_items = [
      { name: "Pork Chop Suey", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 13.95 },
      { name: "Pork Chow Mein", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 13.95 },
      { name: "Sweet and Sour Pork", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 13.95 }
    ]
    
    pork_items.each do |item|
      create_menu_item(main_menu, categories[:pork], item[:name], item[:description], item[:price])
    end
    
    # PANCIT
    log "Creating pancit items...", :info
    pancit_items = [
      { name: "Combination Pancit", description: "Shrimp, Chicken, Beef, and Pork with Canton, Fresh Egg, or Bihon Noodles", price: 15.50 },
      { name: "Shrimp Pancit", description: "With Canton, Fresh Egg, or Bihon Noodles", price: 13.50 },
      { name: "Chicken Pancit", description: "With Canton, Fresh Egg, or Bihon Noodles", price: 13.50 },
      { name: "Beef Pancit", description: "With Canton, Fresh Egg, or Bihon Noodles", price: 13.50 },
      { name: "Pork Pancit", description: "With Canton, Fresh Egg, or Bihon Noodles", price: 13.50 }
    ]
    
    pancit_items.each do |item|
      create_menu_item(main_menu, categories[:pancit], item[:name], item[:description], item[:price])
    end
    
    # CHINESE APPETIZERS
    log "Creating Chinese appetizer items...", :info
    chinese_appetizer_items = [
      { name: "Egg Rolls", price: 12.95 },
      { name: "Fried Wonton", price: 12.95 },
      { name: "Crab Rangoon", price: 13.95 },
      { name: "Pork Siomai", description: "10 pcs", price: 13.25 },
      { name: "Shrimp Siomai", description: "10 pcs", price: 14.95 }
    ]
    
    chinese_appetizer_items.each do |item|
      create_menu_item(main_menu, categories[:chinese_appetizers], item[:name], item[:description], item[:price])
    end
    
    # SOUP
    log "Creating soup items...", :info
    soup_items = [
      { name: "Egg Flower Soup", price: 11.95 },
      { name: "Corn Soup", price: 11.95 },
      { name: "Wonton Soup", price: 13.95 },
      { name: "Wonton Mein Soup", price: 13.95 },
      { name: "Hototay Soup", price: 13.95 }
    ]
    
    soup_items.each do |item|
      create_menu_item(main_menu, categories[:soup], item[:name], item[:description], item[:price])
    end
    
    # FISH
    log "Creating fish items...", :info
    fish_items = [
      { name: "Sweet and Sour Basa", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 15.50 },
      { name: "Sweet and Sour MahiMahi", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 15.50 },
      { name: "Chili Oil Glazed Steamed Basa", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 16.45 },
      { name: "Chili Oil Glazed Steamed MahiMahi", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 16.45 }
    ]
    
    fish_items.each do |item|
      create_menu_item(main_menu, categories[:fish], item[:name], item[:description], item[:price])
    end
    
    # DUCK
    log "Creating duck items...", :info
    duck_items = [
      { name: "Roasted Duck", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 17.95 },
      { name: "Sweet and Sour Duck with Pineapple", description: "Served with steamed rice. Add $1.00 for House Fried Rice.", price: 17.95 }
    ]
    
    duck_items.each do |item|
      create_menu_item(main_menu, categories[:duck], item[:name], item[:description], item[:price])
    end
    
    # CRISPY NOODLES
    log "Creating crispy noodles items...", :info
    crispy_noodles_items = [
      { name: "Crispy Noodles with Shrimp", price: 13.50 },
      { name: "Crispy Noodles with Beef", price: 13.50 },
      { name: "Crispy Noodles with Chicken", price: 13.00 },
      { name: "Crispy Noodles with Pork", price: 13.00 }
    ]
    
    crispy_noodles_items.each do |item|
      create_menu_item(main_menu, categories[:crispy_noodles], item[:name], item[:description], item[:price])
    end
    
    # FRIED RICE
    log "Creating fried rice items...", :info
    fried_rice_items = [
      { name: "Chicken Fried Rice", price: 12.45 },
      { name: "Shrimp Fried Rice", price: 13.45 },
      { name: "Ground Pork Fried Rice", price: 12.45 },
      { name: "Teppanyaki Fried Rice", price: 12.45 },
      { name: "Shanghai Fried Rice", price: 14.45 },
      { name: "House Fried Rice (Plate)", price: 9.50 },
      { name: "House Fried Rice (Bowl)", price: 5.75 },
      { name: "Steamed Rice", price: 3.00 }
    ]
    
    fried_rice_items.each do |item|
      create_menu_item(main_menu, categories[:fried_rice], item[:name], item[:description], item[:price])
    end
    
    # MIXED CUISINE
    log "Creating mixed cuisine items...", :info
    mixed_cuisine_items = [
      { name: "Thai Pork Salad", price: 8.50 },
      { name: "Mandarin Chicken Salad", price: 8.50 },
      { name: "Niçoise Salad", price: 7.50 },
      { name: "Caesar Salad", price: 7.50 },
      { name: "Broccoli Crab Salad", price: 7.50 },
      { name: "Garden Green Salad", price: 6.50 }
    ]
    
    mixed_cuisine_items.each do |item|
      create_menu_item(main_menu, categories[:mixed_cuisine], item[:name], item[:description], item[:price])
    end
    
    # BURGERS / SANDWICHES
    log "Creating burgers and sandwiches items...", :info
    burgers_sandwiches_items = [
      { name: "Chef's Burger", description: "Served with French Fries", price: 13.95 },
      { name: "Chin Fe Burger", description: "Served with French Fries", price: 13.50 },
      { name: "Grilled Mushroom Burger", description: "Served with French Fries", price: 13.50 },
      { name: "Egg Burger", description: "Served with French Fries", price: 13.50 },
      { name: "Classic Club Sandwich", description: "Served with French Fries", price: 12.50 },
      { name: "Ham, Egg, & Cheese Sandwich", description: "Served with French Fries", price: 12.50 },
      { name: "Fish Cutlet Sandwich", description: "Served with French Fries", price: 13.50 },
      { name: "Shrimp Po Boy Sandwich", description: "Served with French Fries", price: 16.50 },
      { name: "Katsu Sandwich", description: "Served with French Fries", price: 13.95 },
      { name: "BLT Sandwich", description: "Served with French Fries", price: 11.50 },
      { name: "Grilled Cheese Sandwich", description: "Served with French Fries", price: 8.50 }
    ]
    
    burgers_sandwiches_items.each do |item|
      create_menu_item(main_menu, categories[:burgers_sandwiches], item[:name], item[:description], item[:price])
    end
    
    # STEAK & CHOPS
    log "Creating steak and chops items...", :info
    steak_chops_items = [
      { name: "Hamburger Steak", description: "Served with vegetables and steamed rice. Add $1.00 for House Fried Rice", price: 16.50 },
      { name: "Grilled Pork Chop", description: "2 pieces. Served with vegetables and steamed rice. Add $1.00 for House Fried Rice", price: 16.75 },
      { name: "Fried Pork Chop", description: "2 pieces. Served with vegetables and steamed rice. Add $1.00 for House Fried Rice", price: 16.75 },
      { name: "Charbroiled Pork Chop", description: "2 pieces. Served with vegetables and steamed rice. Add $1.00 for House Fried Rice", price: 16.75 }
    ]
    
    steak_chops_items.each do |item|
      create_menu_item(main_menu, categories[:steak_chops], item[:name], item[:description], item[:price])
    end
    
    # FILIPINO
    log "Creating Filipino items...", :info
    filipino_items = [
      { name: "Classic Sinigang Milk Fish Belly", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.95 },
      { name: "Classic Sinigang Pork Belly", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 15.95 },
      { name: "Classic Sinigang Shrimp", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 17.95 },
      { name: "Crispy Pork Belly KareKare", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 18.95 },
      { name: "Crispy Pata", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 19.95 },
      { name: "Classic Chicken Adobo", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 15.45 },
      { name: "Bistek Tagalog", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.95 },
      { name: "LechonKawali", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.45 },
      { name: "Pork Adobo", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.45 }
    ]
    
    filipino_items.each do |item|
      create_menu_item(main_menu, categories[:filipino], item[:name], item[:description], item[:price])
    end
    
    # JAPANESE
    log "Creating Japanese items...", :info
    japanese_items = [
      { name: "Beef Curry", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.95 },
      { name: "Chicken Cutlet", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.45 },
      { name: "Chicken Teriyaki", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.45 },
      { name: "Chicken Karaage", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.45 }
    ]
    
    japanese_items.each do |item|
      create_menu_item(main_menu, categories[:japanese], item[:name], item[:description], item[:price])
    end
    
    # KOREAN
    log "Creating Korean items...", :info
    korean_items = [
      { name: "Korean Style Short Ribs", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 18.95 },
      { name: "Kimchi Pork", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.45 },
      { name: "Beef Bulgogi", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.95 },
      { name: "Korean Style Soy Sauce Chicken Wings", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.95 },
      { name: "Japchae", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 14.25 }
    ]
    
    korean_items.each do |item|
      create_menu_item(main_menu, categories[:korean], item[:name], item[:description], item[:price])
    end
    
    # ITALIAN
    log "Creating Italian items...", :info
    italian_items = [
      { name: "Spaghetti Carbonara", price: 14.50 },
      { name: "Spaghetti with Meat Sauce", price: 14.50 },
      { name: "Spaghetti with Marinara", price: 14.50 },
      { name: "Spaghetti Vongole", price: 14.50 },
      { name: "Spaghetti Pepperoncino", price: 14.50 },
      { name: "Shrimp Scampi", price: 14.50 }
    ]
    
    italian_items.each do |item|
      create_menu_item(main_menu, categories[:italian], item[:name], item[:description], item[:price])
    end
    
    # CHAMORRO APPETIZERS
    log "Creating Chamorro appetizer items...", :info
    chamorro_appetizer_items = [
      { name: "Beef Kelaguen", price: 13.25 },
      { name: "Chicken Kelaguen with Titiyas", price: 12.50 },
      { name: "Tuna Poke", description: "Bowl", price: 16.50 },
      { name: "Tuna Tataki with Ponzu Sauce", price: 16.50 }
    ]
    
    chamorro_appetizer_items.each do |item|
      create_menu_item(main_menu, categories[:chamorro_appetizers], item[:name], item[:description], item[:price])
    end
    
    # CHAMORRO ENTREES
    log "Creating Chamorro entree items...", :info
    chamorro_entree_items = [
      { name: "Tinaktak", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 15.95 },
      { name: "Chicken Estufao", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 15.95 },
      { name: "Beef Estufao", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.95 },
      { name: "Pork Estufao", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.95 },
      { name: "Kadun Pika", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 16.95 },
      { name: "Kadun Manok", description: "Served with steamed rice. Add $1.00 for House Fried Rice", price: 15.95 }
    ]
    
    chamorro_entree_items.each do |item|
      create_menu_item(main_menu, categories[:chamorro_entrees], item[:name], item[:description], item[:price])
    end
    
    # BEVERAGES
    log "Creating beverage items...", :info
    beverage_items = [
      { name: "Iced Tea", price: 3.50 },
      { name: "Lemonade", price: 3.50 },
      { name: "Coke", price: 3.00 },
      { name: "Diet Coke", price: 3.00 },
      { name: "Sprite", price: 3.00 },
      { name: "Bottled Water", price: 2.50 },
      { name: "Hot Coffee", price: 3.00 },
      { name: "Hot Tea", price: 3.00 },
      { name: "Milk", price: 3.00 },
      { name: "Orange Juice", price: 3.50 },
      { name: "Apple Juice", price: 3.50 }
    ]
    
    beverage_items.each do |item|
      create_menu_item(main_menu, categories[:beverages], item[:name], item[:description], item[:price])
    end
    
    # DESSERTS
    log "Creating dessert items...", :info
    dessert_items = [
      { name: "Mango Pudding", price: 6.50 },
      { name: "Almond Pudding", price: 6.50 },
      { name: "Coconut Pudding", price: 6.50 },
      { name: "Latiya", description: "Chamorro vanilla custard cake", price: 6.50 },
      { name: "Ice Cream", description: "Vanilla, Chocolate, or Strawberry", price: 5.50 },
      { name: "Fried Banana with Ice Cream", price: 7.50 }
    ]
    
    dessert_items.each do |item|
      create_menu_item(main_menu, categories[:desserts], item[:name], item[:description], item[:price])
    end
    
    log "All menu items created successfully!", :info
  end
  
rescue => e
  log "ERROR: #{e.message}", :error
  log e.backtrace.join("\n"), :error
  raise e
ensure
  # Reset tenant context
  ActiveRecord::Base.current_restaurant = nil
  log "Tenant context reset", :info
  log_file.close
end
