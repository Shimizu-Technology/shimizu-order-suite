namespace :wholesale do
  desc "Migrate existing variants to option groups system"
  task migrate_variants_to_options: :environment do
    puts "🚀 Starting Variant to Option Groups Migration"
    puts "=" * 60
    
    # Statistics tracking
    stats = {
      items_processed: 0,
      items_with_variants: 0,
      option_groups_created: 0,
      options_created: 0,
      sales_data_migrated: 0,
      errors: []
    }
    
    begin
      # Find all items with variants
      items_with_variants = Wholesale::Item.joins(:variants).distinct
      
      puts "Found #{items_with_variants.count} items with variants to migrate"
      puts
      
      items_with_variants.find_each do |item|
        stats[:items_processed] += 1
        
        puts "Processing Item ##{item.id}: #{item.name}"
        
        # Skip if item already has option groups
        if item.option_groups.exists?
          puts "  ⚠️  Item already has option groups, skipping..."
          next
        end
        
        stats[:items_with_variants] += 1
        
        # Analyze variants to determine option groups needed
        variants = item.variants.includes(:wholesale_item)
        
        # Group variants by their attributes
        size_variants = variants.where.not(size: [nil, '']).distinct.pluck(:size).compact
        color_variants = variants.where.not(color: [nil, '']).distinct.pluck(:color).compact
        
        puts "  📊 Found #{variants.count} variants"
        puts "  📏 Sizes: #{size_variants.join(', ')}" if size_variants.any?
        puts "  🎨 Colors: #{color_variants.join(', ')}" if color_variants.any?
        
        # Create Size option group if needed
        size_group = nil
        if size_variants.any?
          size_group = item.option_groups.create!(
            name: 'Size',
            min_select: 1,
            max_select: 1,
            required: true,
            position: 1,
            enable_inventory_tracking: false
          )
          stats[:option_groups_created] += 1
          
          puts "  ✅ Created Size option group"
          
          # Create size options
          size_variants.each_with_index do |size, index|
            # Find a representative variant for this size to get pricing info
            representative_variant = variants.find_by(size: size)
            
            option = size_group.options.create!(
              name: size,
              additional_price: representative_variant&.price_adjustment || 0.0,
              available: true,
              position: index + 1,
              stock_quantity: nil,
              damaged_quantity: 0,
              low_stock_threshold: nil,
              total_ordered: 0,
              total_revenue: 0.0
            )
            stats[:options_created] += 1
            
            puts "    📦 Created size option: #{size} (+$#{option.additional_price})"
          end
        end
        
        # Create Color option group if needed
        color_group = nil
        if color_variants.any?
          color_group = item.option_groups.create!(
            name: 'Color',
            min_select: 1,
            max_select: 1,
            required: true,
            position: 2,
            enable_inventory_tracking: false
          )
          stats[:option_groups_created] += 1
          
          puts "  ✅ Created Color option group"
          
          # Create color options
          color_variants.each_with_index do |color, index|
            # Find a representative variant for this color to get pricing info
            representative_variant = variants.find_by(color: color)
            
            option = color_group.options.create!(
              name: color,
              additional_price: representative_variant&.price_adjustment || 0.0,
              available: true,
              position: index + 1,
              stock_quantity: nil,
              damaged_quantity: 0,
              low_stock_threshold: nil,
              total_ordered: 0,
              total_revenue: 0.0
            )
            stats[:options_created] += 1
            
            puts "    🎨 Created color option: #{color} (+$#{option.additional_price})"
          end
        end
        
        # Migrate sales data from variants to options
        puts "  📈 Migrating sales data..."
        
        variants.each do |variant|
          next if variant.total_ordered == 0 && variant.total_revenue == 0
          
          # Find corresponding options
          size_option = size_group&.options&.find_by(name: variant.size) if variant.size.present?
          color_option = color_group&.options&.find_by(name: variant.color) if variant.color.present?
          
          # Distribute sales data to options
          if size_option
            size_option.increment!(:total_ordered, variant.total_ordered)
            size_option.increment!(:total_revenue, variant.total_revenue)
            stats[:sales_data_migrated] += 1
          end
          
          if color_option
            color_option.increment!(:total_ordered, variant.total_ordered)
            color_option.increment!(:total_revenue, variant.total_revenue)
            stats[:sales_data_migrated] += 1
          end
          
          puts "    💰 Migrated sales: #{variant.display_name} (#{variant.total_ordered} orders, $#{variant.total_revenue})"
        end
        
        puts "  ✅ Item migration completed"
        puts
        
      rescue StandardError => e
        error_msg = "Error processing item ##{item&.id}: #{e.message}"
        stats[:errors] << error_msg
        puts "  ❌ #{error_msg}"
        puts
      end
      
      # Print final statistics
      puts
      puts "🎉 Migration Completed!"
      puts "=" * 60
      puts "📊 Statistics:"
      puts "  • Items processed: #{stats[:items_processed]}"
      puts "  • Items with variants: #{stats[:items_with_variants]}"
      puts "  • Option groups created: #{stats[:option_groups_created]}"
      puts "  • Options created: #{stats[:options_created]}"
      puts "  • Sales data entries migrated: #{stats[:sales_data_migrated]}"
      puts "  • Errors: #{stats[:errors].count}"
      
      if stats[:errors].any?
        puts
        puts "❌ Errors encountered:"
        stats[:errors].each { |error| puts "  • #{error}" }
      end
      
      puts
      puts "✅ Variant to Option Groups migration completed successfully!"
      puts
      puts "📋 Next Steps:"
      puts "  1. Test the new option groups in the admin interface"
      puts "  2. Verify pricing and sales data accuracy"
      puts "  3. Run the cleanup task to remove old variant system"
      puts "  4. Update any custom code that references variants"
      
    rescue StandardError => e
      puts "💥 Fatal error during migration: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      raise e
    end
  end
  
  desc "Verify migration results and show comparison"
  task verify_migration: :environment do
    puts "🔍 Verifying Variant to Option Groups Migration"
    puts "=" * 60
    
    # Compare old vs new system
    items_with_variants = Wholesale::Item.joins(:variants).distinct
    items_with_options = Wholesale::Item.joins(:option_groups).distinct
    
    puts "📊 System Comparison:"
    puts "  • Items with variants: #{items_with_variants.count}"
    puts "  • Items with option groups: #{items_with_options.count}"
    puts "  • Items with both systems: #{(items_with_variants & items_with_options).count}"
    
    puts
    puts "📋 Detailed Analysis:"
    
    items_with_variants.limit(5).each do |item|
      puts
      puts "Item: #{item.name}"
      
      # Variant data
      variants = item.variants
      total_variant_sales = variants.sum(:total_ordered)
      total_variant_revenue = variants.sum(:total_revenue)
      
      puts "  Variants (#{variants.count}):"
      variants.each do |variant|
        puts "    • #{variant.display_name}: #{variant.total_ordered} orders, $#{variant.total_revenue}"
      end
      
      # Option data
      if item.option_groups.exists?
        puts "  Option Groups (#{item.option_groups.count}):"
        item.option_groups.each do |group|
          puts "    #{group.name}:"
          group.options.each do |option|
            puts "      • #{option.name}: #{option.total_ordered} orders, $#{option.total_revenue}"
          end
        end
        
        total_option_sales = item.options.sum(:total_ordered)
        total_option_revenue = item.options.sum(:total_revenue)
        
        puts "  📊 Sales Comparison:"
        puts "    • Variant totals: #{total_variant_sales} orders, $#{total_variant_revenue}"
        puts "    • Option totals: #{total_option_sales} orders, $#{total_option_revenue}"
        
        if total_variant_sales != total_option_sales || total_variant_revenue.round(2) != total_option_revenue.round(2)
          puts "    ⚠️  Sales data mismatch detected!"
        else
          puts "    ✅ Sales data matches"
        end
      else
        puts "  ❌ No option groups found for this item"
      end
    end
    
    puts
    puts "✅ Migration verification completed"
  end
  
  desc "Rollback migration (restore from variants)"
  task rollback_migration: :environment do
    puts "⚠️  Rolling back Option Groups Migration"
    puts "=" * 60
    
    print "Are you sure you want to delete all option groups? (yes/no): "
    confirmation = STDIN.gets.chomp
    
    unless confirmation.downcase == 'yes'
      puts "❌ Rollback cancelled"
      exit
    end
    
    puts "🗑️  Removing all option groups and options..."
    
    deleted_options = Wholesale::Option.count
    deleted_groups = Wholesale::OptionGroup.count
    
    Wholesale::Option.delete_all
    Wholesale::OptionGroup.delete_all
    
    puts "✅ Rollback completed:"
    puts "  • Deleted #{deleted_options} options"
    puts "  • Deleted #{deleted_groups} option groups"
    puts
    puts "⚠️  Note: Variant data was preserved during rollback"
  end
end