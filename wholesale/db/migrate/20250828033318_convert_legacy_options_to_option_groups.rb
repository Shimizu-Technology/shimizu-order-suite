class ConvertLegacyOptionsToOptionGroups < ActiveRecord::Migration[7.2]
  def up
    puts "Converting legacy options to option groups..."
    
    # Find all items that have legacy options but need conversion
    items_to_convert = Wholesale::Item.where.not(options: [nil, {}])
    
    puts "Found #{items_to_convert.count} items with legacy options"
    
    items_to_convert.find_each do |item|
      next unless item.options.is_a?(Hash)
      
      puts "Converting item: #{item.name} (ID: #{item.id})"
      
      # Extract legacy options
      size_options = item.options['size_options'] || []
      color_options = item.options['color_options'] || []
      
      # Skip if no options to convert
      if size_options.empty? && color_options.empty?
        puts "  No size or color options found, skipping"
        next
      end
      
      # Create Size option group if size options exist
      if size_options.any?
        puts "  Creating Size option group with #{size_options.length} options"
        
        size_group = item.option_groups.create!(
          name: 'Size',
          min_select: 1,
          max_select: 1,
          required: true,
          position: 1,
          enable_inventory_tracking: false
        )
        
        size_options.each_with_index do |size, index|
          size_group.options.create!(
            name: size,
            additional_price: 0.0,
            available: true,
            position: index + 1,
            stock_quantity: nil,
            damaged_quantity: 0,
            low_stock_threshold: nil,
            total_ordered: 0,
            total_revenue: 0.0
          )
        end
      end
      
      # Create Color option group if color options exist
      if color_options.any?
        puts "  Creating Color option group with #{color_options.length} options"
        
        color_group = item.option_groups.create!(
          name: 'Color',
          min_select: 1,
          max_select: 1,
          required: true,
          position: 2,
          enable_inventory_tracking: false
        )
        
        color_options.each_with_index do |color, index|
          color_group.options.create!(
            name: color,
            additional_price: 0.0,
            available: true,
            position: index + 1,
            stock_quantity: nil,
            damaged_quantity: 0,
            low_stock_threshold: nil,
            total_ordered: 0,
            total_revenue: 0.0
          )
        end
      end
      
      # Clear the legacy options field
      item.update_column(:options, {})
      puts "  ✅ Converted and cleared legacy options"
      
    rescue StandardError => e
      puts "  ❌ Error converting item #{item.id}: #{e.message}"
      # Continue with next item rather than failing the entire migration
    end
    
    puts "✅ Legacy options conversion complete!"
  end
  
  def down
    puts "Reverting option groups back to legacy options..."
    
    # Find items that have option groups but empty legacy options
    items_to_revert = Wholesale::Item.joins(:option_groups)
      .where(options: [nil, {}])
      .distinct
    
    puts "Found #{items_to_revert.count} items to revert"
    
    items_to_revert.find_each do |item|
      puts "Reverting item: #{item.name} (ID: #{item.id})"
      
      legacy_options = {
        'size_options' => [],
        'color_options' => [],
        'custom_fields' => {}
      }
      
      item.option_groups.each do |group|
        case group.name.downcase
        when 'size'
          legacy_options['size_options'] = group.options.order(:position).pluck(:name)
          puts "  Restored #{legacy_options['size_options'].length} size options"
        when 'color'
          legacy_options['color_options'] = group.options.order(:position).pluck(:name)
          puts "  Restored #{legacy_options['color_options'].length} color options"
        else
          puts "  Skipping unknown option group: #{group.name}"
        end
      end
      
      # Update the legacy options field
      item.update_column(:options, legacy_options)
      
      # Delete the option groups and their options
      item.option_groups.destroy_all
      
      puts "  ✅ Reverted to legacy options"
      
    rescue StandardError => e
      puts "  ❌ Error reverting item #{item.id}: #{e.message}"
    end
    
    puts "✅ Reversion to legacy options complete!"
  end
end