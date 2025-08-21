# db/seeds/wholesale_option_group_presets.rb
# Create default option group presets for wholesale items

puts "Creating default wholesale option group presets..."

# Find all restaurants to create presets for
Restaurant.find_each do |restaurant|
  puts "  Creating presets for restaurant: #{restaurant.name}"
  
  # Youth & Adult Sizes preset
  unless restaurant.wholesale_option_group_presets.exists?(name: "Youth & Adult Sizes")
    preset = restaurant.wholesale_option_group_presets.create!(
      name: "Youth & Adult Sizes",
      description: "Standard youth and adult size options for apparel",
      min_select: 1,
      max_select: 1,
      required: true,
      position: 1,
      enable_inventory_tracking: false
    )
    
    # Create size options
    size_options = [
      { name: "Youth XS", additional_price: 0, available: true, position: 1 },
      { name: "Youth S", additional_price: 0, available: true, position: 2 },
      { name: "Youth M", additional_price: 0, available: true, position: 3 },
      { name: "Youth L", additional_price: 0, available: true, position: 4 },
      { name: "Youth XL", additional_price: 0, available: true, position: 5 },
      { name: "Adult S", additional_price: 2, available: true, position: 6 },
      { name: "Adult M", additional_price: 2, available: true, position: 7 },
      { name: "Adult L", additional_price: 2, available: true, position: 8 },
      { name: "Adult XL", additional_price: 2, available: true, position: 9 },
      { name: "Adult 2XL", additional_price: 4, available: true, position: 10 },
      { name: "Adult 3XL", additional_price: 6, available: true, position: 11 }
    ]
    
    size_options.each do |option_data|
      preset.option_presets.create!(option_data)
    end
    
    puts "    Created: Youth & Adult Sizes preset with #{size_options.length} options"
  end
  
  # Standard Colors preset
  unless restaurant.wholesale_option_group_presets.exists?(name: "Standard Colors")
    preset = restaurant.wholesale_option_group_presets.create!(
      name: "Standard Colors",
      description: "Basic color options for apparel and accessories",
      min_select: 1,
      max_select: 1,
      required: true,
      position: 2,
      enable_inventory_tracking: false
    )
    
    # Create color options
    color_options = [
      { name: "Black", additional_price: 0, available: true, position: 1 },
      { name: "White", additional_price: 0, available: true, position: 2 },
      { name: "Navy", additional_price: 0, available: true, position: 3 },
      { name: "Gray", additional_price: 0, available: true, position: 4 },
      { name: "Red", additional_price: 0, available: true, position: 5 },
      { name: "Royal Blue", additional_price: 0, available: true, position: 6 },
      { name: "Forest Green", additional_price: 0, available: true, position: 7 },
      { name: "Maroon", additional_price: 0, available: true, position: 8 }
    ]
    
    color_options.each do |option_data|
      preset.option_presets.create!(option_data)
    end
    
    puts "    Created: Standard Colors preset with #{color_options.length} options"
  end
  
  # Adult Sizes Only preset
  unless restaurant.wholesale_option_group_presets.exists?(name: "Adult Sizes Only")
    preset = restaurant.wholesale_option_group_presets.create!(
      name: "Adult Sizes Only",
      description: "Adult size options for items not available in youth sizes",
      min_select: 1,
      max_select: 1,
      required: true,
      position: 3,
      enable_inventory_tracking: false
    )
    
    # Create adult size options
    adult_size_options = [
      { name: "S", additional_price: 0, available: true, position: 1 },
      { name: "M", additional_price: 0, available: true, position: 2 },
      { name: "L", additional_price: 0, available: true, position: 3 },
      { name: "XL", additional_price: 0, available: true, position: 4 },
      { name: "2XL", additional_price: 2, available: true, position: 5 },
      { name: "3XL", additional_price: 4, available: true, position: 6 },
      { name: "4XL", additional_price: 6, available: true, position: 7 }
    ]
    
    adult_size_options.each do |option_data|
      preset.option_presets.create!(option_data)
    end
    
    puts "    Created: Adult Sizes Only preset with #{adult_size_options.length} options"
  end
  
  # Premium Colors preset
  unless restaurant.wholesale_option_group_presets.exists?(name: "Premium Colors")
    preset = restaurant.wholesale_option_group_presets.create!(
      name: "Premium Colors",
      description: "Premium color options with additional cost",
      min_select: 1,
      max_select: 1,
      required: true,
      position: 4,
      enable_inventory_tracking: false
    )
    
    # Create premium color options
    premium_color_options = [
      { name: "Black", additional_price: 0, available: true, position: 1 },
      { name: "White", additional_price: 0, available: true, position: 2 },
      { name: "Navy", additional_price: 0, available: true, position: 3 },
      { name: "Heather Gray", additional_price: 1, available: true, position: 4 },
      { name: "Vintage Red", additional_price: 2, available: true, position: 5 },
      { name: "Sunset Orange", additional_price: 2, available: true, position: 6 },
      { name: "Electric Blue", additional_price: 2, available: true, position: 7 },
      { name: "Forest Green", additional_price: 1, available: true, position: 8 },
      { name: "Deep Purple", additional_price: 2, available: true, position: 9 },
      { name: "Gold", additional_price: 3, available: true, position: 10 }
    ]
    
    premium_color_options.each do |option_data|
      preset.option_presets.create!(option_data)
    end
    
    puts "    Created: Premium Colors preset with #{premium_color_options.length} options"
  end
  
  # Material Options preset
  unless restaurant.wholesale_option_group_presets.exists?(name: "Material Options")
    preset = restaurant.wholesale_option_group_presets.create!(
      name: "Material Options",
      description: "Different material choices with varying prices",
      min_select: 1,
      max_select: 1,
      required: true,
      position: 5,
      enable_inventory_tracking: false
    )
    
    # Create material options
    material_options = [
      { name: "Cotton", additional_price: 0, available: true, position: 1 },
      { name: "Cotton Blend", additional_price: 1, available: true, position: 2 },
      { name: "Performance Fabric", additional_price: 3, available: true, position: 3 },
      { name: "Organic Cotton", additional_price: 2, available: true, position: 4 },
      { name: "Bamboo Blend", additional_price: 4, available: true, position: 5 }
    ]
    
    material_options.each do |option_data|
      preset.option_presets.create!(option_data)
    end
    
    puts "    Created: Material Options preset with #{material_options.length} options"
  end
  
  puts "  Completed presets for restaurant: #{restaurant.name}"
end

puts "Wholesale option group presets seeding completed!"
puts "Created presets: Youth & Adult Sizes, Standard Colors, Adult Sizes Only, Premium Colors, Material Options"
