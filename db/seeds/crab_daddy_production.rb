# crab_daddy_production.rb
# A script to create a complete menu structure for Crab Daddy in production
# This script handles proper tenant isolation and error handling

require 'logger'

# Initialize logger
log_file = File.open("#{Rails.root}/log/crab_daddy_menu_setup_#{Time.now.strftime('%Y%m%d%H%M%S')}.log", 'w')
$logger = Logger.new(log_file)
$logger.level = Logger::INFO

# Also log to STDOUT
$console_logger = Logger.new(STDOUT)
$console_logger.level = Logger::INFO

def log(message, level = :info)
  $logger.send(level, message)
  $console_logger.send(level, message)
end

log "Starting Crab Daddy menu setup script", :info
log "======================================", :info

# Find the Crab Daddy restaurant by name
restaurant_name = "Crab Daddy"

begin
  # Find the restaurant by name
  restaurant = Restaurant.find_by!(name: restaurant_name)
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
    menu_name = "Crab Daddy Menu #{Time.now.strftime('%Y%m%d_%H%M%S')}"
    
    main_menu = Menu.create!(
      restaurant_id: restaurant.id,
      name: menu_name,
      active: false # Set to false as requested
    )
    
    log "Created new menu: #{main_menu.name} (ID: #{main_menu.id})", :info
    
    # 2. Create categories
    log "Creating categories...", :info
    categories = {}
    
    # Define categories for Crab Daddy
    category_names = {
      cocktails: "COCKTAILS",
      shareables: "SHAREABLES",
      seafood_combos: "SEAFOOD COMBOS",
      build_your_own: "BUILD-YOUR-OWN SEAFOOD BOIL",
      appetizers: "APPETIZERS",
      salads: "SALADS",
      po_boys: "PO' BOYS",
      kids_menu: "KID'S MENU",
      baskets: "BASKETS",
      entrees: "GRILLED ENTRÉES",
      extras: "EXTRAS",
      beverages: "BEVERAGES",
      milkshakes: "MILKSHAKES",
      ice_cream: "ICE CREAM",
      beer: "BEER",
      wine: "WINE",
      fish_bowl_cocktails: "FISH-BOWL COCKTAILS"
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
    
    # 3. Create menu items for each category
    log "Creating menu items...", :info
    
    # COCKTAILS - $8.99 each
    log "Creating cocktail items...", :info
    cocktail_items = [
      { name: "Aloha Delight", description: "Spiced rum, pineapple juice, Sprite", price: 8.99 },
      { name: "Hurricane 5", description: "White & dark rum, orange & pineapple juices, grenadine", price: 8.99 },
      { name: "Island Breeze", description: "Coconut rum, pineapple juice, cranberry juice", price: 8.99 },
      { name: "Mango Tango", description: "Vodka, mango puree, orange juice, lime", price: 8.99 },
      { name: "Ocean Blue", description: "Vodka, blue curacao, lemonade, sprite", price: 8.99 },
      { name: "Piña Colada", description: "Rum, coconut cream, pineapple juice", price: 8.99 },
      { name: "Rum Punch", description: "Light & dark rum, orange juice, pineapple juice, grenadine", price: 8.99 },
      { name: "Seafarer's Margarita", description: "Tequila, triple sec, lime juice, salt rim", price: 8.99 },
      { name: "Sex on the Beach", description: "Vodka, peach schnapps, orange & cranberry juices", price: 8.99 },
      { name: "Zombie", description: "Light & dark rum, apricot brandy, lime juice, pineapple juice", price: 8.99 }
    ]
    
    cocktail_items.each do |item|
      create_menu_item(main_menu, categories[:cocktails], item[:name], item[:description], item[:price])
    end
    
    # SHAREABLES
    log "Creating shareable items...", :info
    shareable_items = [
      { name: "Crab Daddy's Seafood Platter", description: "A shareable feast with snow crab, shrimp, mussels, clams, corn, potatoes & sausage in our signature Cajun sauce", price: 79.95 },
      { name: "Lobster & Crab Feast", description: "1 whole lobster, 1 lb snow crab, corn, potatoes & sausage in garlic butter sauce", price: 89.95 },
      { name: "Seafood Boil Family Pack", description: "2 lbs of mixed seafood with corn, potatoes & sausage in your choice of sauce", price: 69.95 }
    ]
    
    shareable_items.each do |item|
      create_menu_item(main_menu, categories[:shareables], item[:name], item[:description], item[:price])
    end
    
    # SEAFOOD COMBOS
    log "Creating seafood combo items...", :info
    combo_items = [
      { name: "Combo #1", description: "1/2 lb shrimp, 1/2 lb mussels, 1/2 lb clams, corn, potatoes & sausage", price: 39.95 },
      { name: "Combo #2", description: "1/2 lb snow crab, 1/2 lb shrimp, 1/2 lb mussels, corn, potatoes & sausage", price: 49.95 },
      { name: "Combo #3", description: "1/2 lb snow crab, 1/2 lb crawfish, 1/2 lb clams, corn, potatoes & sausage", price: 49.95 },
      { name: "Combo #4", description: "1/2 lb lobster, 1/2 lb shrimp, 1/2 lb mussels, corn, potatoes & sausage", price: 59.95 },
      { name: "Combo #5", description: "1/2 lb dungeness crab, 1/2 lb shrimp, 1/2 lb clams, corn, potatoes & sausage", price: 59.95 }
    ]
    
    combo_items.each do |item|
      create_menu_item(main_menu, categories[:seafood_combos], item[:name], item[:description], item[:price])
    end
    
    # BUILD-YOUR-OWN SEAFOOD BOIL
    log "Creating Build Your Own Seafood Boil with option groups...", :info
    
    # Create the base menu item
    build_your_own = create_menu_item(
      main_menu, 
      categories[:build_your_own], 
      "Build Your Own Seafood Boil", 
      "Create your own custom seafood boil", 
      15.95
    )
    
    # Create option groups and options
    seafood_group = OptionGroup.find_or_create_by!(
      menu_item_id: build_your_own.id,
      name: "Step 1 - Catch It!"
    ) do |group|
      group.min_select = 1
      group.max_select = 5
      group.free_option_count = 0
    end
    
    sauce_group = OptionGroup.find_or_create_by!(
      menu_item_id: build_your_own.id,
      name: "Step 2 - Sauce It!"
    ) do |group|
      group.min_select = 1
      group.max_select = 1
      group.free_option_count = 1
    end
    
    heat_group = OptionGroup.find_or_create_by!(
      menu_item_id: build_your_own.id,
      name: "Step 3 - Heat It!"
    ) do |group|
      group.min_select = 1
      group.max_select = 1
      group.free_option_count = 1
    end
    
    add_on_group = OptionGroup.find_or_create_by!(
      menu_item_id: build_your_own.id,
      name: "Step 4 - Add It!"
    ) do |group|
      group.min_select = 0
      group.max_select = 10
      group.free_option_count = 0
    end
    
    # Seafood options
    seafood_options = [
      { name: "Dungeness Crab (1.75 lb)", price: 45.00 },
      { name: "King Crab (1 lb)", price: 55.00 },
      { name: "Lobster (1.1 lb)", price: 50.00 },
      { name: "Snow Crab (1.25 lb)", price: 40.00 },
      { name: "Baby Octopus", price: 17.95 },
      { name: "Black Mussels", price: 15.95 },
      { name: "Crawfish", price: 16.95 },
      { name: "Sea Scallops", price: 22.95 },
      { name: "Shrimp", price: 19.95 },
      { name: "Squid Rings", price: 17.95 },
      { name: "White Clams", price: 15.95 }
    ]
    
    seafood_options.each do |option_data|
      Option.find_or_create_by!(
        option_group_id: seafood_group.id,
        name: option_data[:name]
      ) do |option|
        option.additional_price = option_data[:price]
        option.is_available = true
      end
    end
    
    # Sauce options
    sauce_options = ["Cajun", "Garlic", "Lemon Pepper", "The Works"]
    sauce_options.each do |sauce|
      Option.find_or_create_by!(
        option_group_id: sauce_group.id,
        name: sauce
      ) do |option|
        option.additional_price = 0.00
        option.is_available = true
      end
    end
    
    # Heat options
    heat_options = ["Non-Spicy", "Medium", "Hot", "Atomic"]
    heat_options.each do |heat|
      Option.find_or_create_by!(
        option_group_id: heat_group.id,
        name: heat
      ) do |option|
        option.additional_price = 0.00
        option.is_available = true
      end
    end
    
    # Add-on options
    add_on_options = [
      { name: "Boiled Egg", price: 1.95 },
      { name: "Corn", price: 0.95 },
      { name: "Noodles", price: 4.95 },
      { name: "Red Potatoes (3 pc)", price: 2.95 },
      { name: "Sausages (3 pc)", price: 4.95 },
      { name: "Rice Cakes", price: 4.95 }
    ]
    
    add_on_options.each do |option_data|
      Option.find_or_create_by!(
        option_group_id: add_on_group.id,
        name: option_data[:name]
      ) do |option|
        option.additional_price = option_data[:price]
        option.is_available = true
      end
    end
    
    log "Created Build Your Own Seafood Boil with option groups", :info
    
    # APPETIZERS
    log "Creating appetizer items...", :info
    appetizer_items = [
      { name: "Breaded Scallops", price: 14.95 },
      { name: "Catfish Nuggets", price: 12.95 },
      { name: "Cocktail Shrimp", price: 12.95 },
      { name: "Coconut Shrimp", price: 16.95 },
      { name: "Crab Claws", price: 13.95 },
      { name: "Fresh Oysters (6 pc)", price: 15.00 },
      { name: "Fresh Oysters (12 pc)", price: 28.00 },
      { name: "Grilled Oysters (6 pc)", price: 17.95 },
      { name: "Fried Calamari", price: 12.95 },
      { name: "Fried Mackerel", price: 12.95 },
      { name: "Fried Oysters", price: 12.95 },
      { name: "Garlic Mussels", price: 14.95 },
      { name: "Popcorn Shrimp", price: 13.95 },
      { name: "Seafood Nachos", price: 16.95 },
      { name: "Seafood Sampler", price: 24.95 },
      { name: "Voodoo Wings", description: "Available in Cajun, Lemon Pepper, Works, or Garlic Parmesan", price: 12.95 }
    ]
    
    appetizer_items.each do |item|
      create_menu_item(main_menu, categories[:appetizers], item[:name], item[:description], item[:price])
    end
    
    # SALADS
    log "Creating salad items...", :info
    salad_items = [
      { name: "Caesar Salad", price: 9.95 },
      { name: "Grilled Chicken Caesar", price: 13.95 },
      { name: "Grilled Shrimp Caesar", price: 15.95 },
      { name: "House Salad", price: 8.95 },
      { name: "Seafood Salad", description: "Mixed greens with shrimp, crab meat & calamari", price: 16.95 }
    ]
    
    salad_items.each do |item|
      create_menu_item(main_menu, categories[:salads], item[:name], item[:description], item[:price])
    end
    
    # PO' BOYS
    log "Creating po' boy items...", :info
    po_boy_items = [
      { name: "Catfish Po' Boy", description: "Served with fries", price: 14.95 },
      { name: "Oyster Po' Boy", description: "Served with fries", price: 15.95 },
      { name: "Shrimp Po' Boy", description: "Served with fries", price: 15.95 },
      { name: "Soft Shell Crab Po' Boy", description: "Served with fries", price: 17.95 }
    ]
    
    po_boy_items.each do |item|
      create_menu_item(main_menu, categories[:po_boys], item[:name], item[:description], item[:price])
    end
    
    # KID'S MENU
    log "Creating kids menu items...", :info
    kids_items = [
      { name: "Chicken Tenders", description: "Served with fries", price: 8.95 },
      { name: "Fried Shrimp", description: "Served with fries", price: 9.95 },
      { name: "Grilled Cheese", description: "Served with fries", price: 7.95 },
      { name: "Mac & Cheese", price: 7.95 }
    ]
    
    kids_items.each do |item|
      create_menu_item(main_menu, categories[:kids_menu], item[:name], item[:description], item[:price])
    end
    
    # BASKETS
    log "Creating basket items...", :info
    basket_items = [
      { name: "Catfish Basket", description: "Served with fries & coleslaw", price: 15.95 },
      { name: "Chicken Tender Basket", description: "Served with fries & coleslaw", price: 14.95 },
      { name: "Oyster Basket", description: "Served with fries & coleslaw", price: 16.95 },
      { name: "Shrimp Basket", description: "Served with fries & coleslaw", price: 16.95 }
    ]
    
    basket_items.each do |item|
      create_menu_item(main_menu, categories[:baskets], item[:name], item[:description], item[:price])
    end
    
    # GRILLED ENTRÉES
    log "Creating entrée items...", :info
    entree_items = [
      { name: "Grilled Basa", description: "Served with rice, coleslaw & steamed vegetables", price: 16.95 },
      { name: "Grilled Catfish", description: "Served with rice, coleslaw & steamed vegetables", price: 18.95 },
      { name: "Grilled Cod", description: "Served with rice, coleslaw & steamed vegetables", price: 19.95 },
      { name: "Grilled Halibut", description: "Served with rice, coleslaw & steamed vegetables", price: 24.95 },
      { name: "Grilled Mahi Mahi", description: "Served with rice, coleslaw & steamed vegetables", price: 22.95 },
      { name: "Grilled Salmon", description: "Served with rice, coleslaw & steamed vegetables", price: 21.95 },
      { name: "Grilled Shrimp", description: "Served with rice, coleslaw & steamed vegetables", price: 19.95 },
      { name: "Grilled Tilapia", description: "Served with rice, coleslaw & steamed vegetables", price: 17.95 }
    ]
    
    entree_items.each do |item|
      create_menu_item(main_menu, categories[:entrees], item[:name], item[:description], item[:price])
    end
    
    # EXTRAS
    log "Creating extra items...", :info
    extra_items = [
      { name: "Cajun Fries", price: 4.95 },
      { name: "Coleslaw", price: 3.95 },
      { name: "Corn (2 pc)", price: 3.95 },
      { name: "French Fries", price: 3.95 },
      { name: "Garlic Bread", price: 3.95 },
      { name: "Garlic Noodles", price: 6.95 },
      { name: "Hush Puppies", price: 4.95 },
      { name: "Red Potatoes (4 pc)", price: 4.95 },
      { name: "Rice", price: 3.95 },
      { name: "Sausages (3 pc)", price: 5.95 },
      { name: "Steamed Vegetables", price: 4.95 }
    ]
    
    extra_items.each do |item|
      create_menu_item(main_menu, categories[:extras], item[:name], item[:description], item[:price])
    end
    
    # BEVERAGES
    log "Creating beverage items...", :info
    beverage_items = [
      { name: "Bottled Water", price: 2.50 },
      { name: "Canned Soda", description: "Coke, Diet Coke, Sprite, Dr. Pepper", price: 2.50 },
      { name: "Fresh Lemonade", price: 3.95 },
      { name: "Iced Tea", price: 2.95 },
      { name: "Juice", description: "Orange, Apple, Cranberry, Pineapple", price: 3.50 }
    ]
    
    beverage_items.each do |item|
      create_menu_item(main_menu, categories[:beverages], item[:name], item[:description], item[:price])
    end
    
    # MILKSHAKES
    log "Creating milkshake items...", :info
    milkshake_items = [
      { name: "Chocolate Milkshake", price: 6.95 },
      { name: "Strawberry Milkshake", price: 6.95 },
      { name: "Vanilla Milkshake", price: 6.95 }
    ]
    
    milkshake_items.each do |item|
      create_menu_item(main_menu, categories[:milkshakes], item[:name], item[:description], item[:price])
    end
    
    # ICE CREAM
    log "Creating ice cream items...", :info
    ice_cream_items = [
      { name: "Chocolate Ice Cream", price: 4.95 },
      { name: "Strawberry Ice Cream", price: 4.95 },
      { name: "Vanilla Ice Cream", price: 4.95 }
    ]
    
    ice_cream_items.each do |item|
      create_menu_item(main_menu, categories[:ice_cream], item[:name], item[:description], item[:price])
    end
    
    # BEER
    log "Creating beer items...", :info
    beer_items = [
      { name: "Budweiser", price: 5.00 },
      { name: "Bud Light", price: 5.00 },
      { name: "Corona", price: 6.00 },
      { name: "Heineken", price: 6.00 },
      { name: "Michelob Ultra", price: 5.50 },
      { name: "Miller Lite", price: 5.00 },
      { name: "Modelo", price: 6.00 },
      { name: "Stella Artois", price: 6.50 }
    ]
    
    beer_items.each do |item|
      create_menu_item(main_menu, categories[:beer], item[:name], item[:description], item[:price])
    end
    
    # WINE
    log "Creating wine items...", :info
    wine_items = [
      { name: "Chardonnay", description: "Glass", price: 8.00 },
      { name: "Merlot", description: "Glass", price: 8.00 },
      { name: "Pinot Grigio", description: "Glass", price: 8.00 },
      { name: "Pinot Noir", description: "Glass", price: 8.00 },
      { name: "Cabernet Sauvignon", description: "Glass", price: 8.00 },
      { name: "White Zinfandel", description: "Glass", price: 8.00 }
    ]
    
    wine_items.each do |item|
      create_menu_item(main_menu, categories[:wine], item[:name], item[:description], item[:price])
    end
    
    # FISH-BOWL COCKTAILS
    log "Creating fish bowl cocktail items...", :info
    fish_bowl_items = [
      { name: "Blue Ocean", description: "Vodka, blue curacao, lemonade, sprite (serves 2-4)", price: 24.95 },
      { name: "Fishbowl Margarita", description: "Tequila, triple sec, lime juice, served with salt rim (serves 2-4)", price: 24.95 },
      { name: "Mermaid's Paradise", description: "Coconut rum, pineapple juice, blue curacao (serves 2-4)", price: 24.95 },
      { name: "Shark Attack", description: "Vodka, rum, blue curacao, sweet & sour, grenadine (serves 2-4)", price: 24.95 },
      { name: "Tropical Tsunami", description: "Light & dark rum, orange & pineapple juices, grenadine (serves 2-4)", price: 24.95 }
    ]
    
    fish_bowl_items.each do |item|
      create_menu_item(main_menu, categories[:fish_bowl_cocktails], item[:name], item[:description], item[:price])
    end
    
    log "All menu items created successfully for Crab Daddy!", :info
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
