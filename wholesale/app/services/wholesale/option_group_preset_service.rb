module Wholesale
  class OptionGroupPresetService
    include TenantScoped
    
    def initialize(restaurant)
      @restaurant = restaurant
    end
    
    # Create a new preset with options
    def create_preset(preset_params, option_presets_data = [])
      preset = @restaurant.wholesale_option_group_presets.build(preset_params)
      
      ActiveRecord::Base.transaction do
        preset.save!
        
        option_presets_data.each_with_index do |option_data, index|
          preset.option_presets.create!(
            name: option_data[:name],
            additional_price: option_data[:additional_price] || 0,
            available: option_data[:available].nil? ? true : option_data[:available],
            position: option_data[:position] || index
          )
        end
      end
      
      preset
    end
    
    # Update a preset and its options
    def update_preset(preset, preset_params, option_presets_data = nil)
      ActiveRecord::Base.transaction do
        preset.update!(preset_params)
        
        if option_presets_data.present?
          # For simplicity, replace all option presets
          # In production, you might want a more sophisticated merge
          preset.option_presets.destroy_all
          
          option_presets_data.each_with_index do |option_data, index|
            preset.option_presets.create!(
              name: option_data[:name],
              additional_price: option_data[:additional_price] || 0,
              available: option_data[:available].nil? ? true : option_data[:available],
              position: option_data[:position] || index
            )
          end
        end
      end
      
      preset
    end
    
    # Apply a preset to multiple items
    def apply_preset_to_items(preset, item_ids)
      items = @restaurant.wholesale_items.where(id: item_ids)
      results = []
      
      items.each do |item|
        begin
          option_group = preset.apply_to_item!(item)
          results << { item_id: item.id, success: true, option_group_id: option_group.id }
        rescue => e
          results << { item_id: item.id, success: false, error: e.message }
        end
      end
      
      results
    end
    
    # Create common presets for a restaurant
    def create_default_presets
      presets = []
      
      # Youth & Adult Sizes preset
      if !@restaurant.wholesale_option_group_presets.exists?(name: "Youth & Adult Sizes")
        preset = create_preset(
          {
            name: "Youth & Adult Sizes",
            description: "Standard youth and adult size options",
            min_select: 1,
            max_select: 1,
            required: true,
            position: 1
          },
          [
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
        )
        presets << preset
      end
      
      # Standard Colors preset
      if !@restaurant.wholesale_option_group_presets.exists?(name: "Standard Colors")
        preset = create_preset(
          {
            name: "Standard Colors",
            description: "Basic color options for apparel",
            min_select: 1,
            max_select: 1,
            required: true,
            position: 2
          },
          [
            { name: "Black", additional_price: 0, available: true, position: 1 },
            { name: "White", additional_price: 0, available: true, position: 2 },
            { name: "Navy", additional_price: 0, available: true, position: 3 },
            { name: "Gray", additional_price: 0, available: true, position: 4 },
            { name: "Red", additional_price: 0, available: true, position: 5 },
            { name: "Royal Blue", additional_price: 0, available: true, position: 6 }
          ]
        )
        presets << preset
      end
      
      # Adult Sizes Only preset
      if !@restaurant.wholesale_option_group_presets.exists?(name: "Adult Sizes Only")
        preset = create_preset(
          {
            name: "Adult Sizes Only",
            description: "Adult size options only",
            min_select: 1,
            max_select: 1,
            required: true,
            position: 3
          },
          [
            { name: "S", additional_price: 0, available: true, position: 1 },
            { name: "M", additional_price: 0, available: true, position: 2 },
            { name: "L", additional_price: 0, available: true, position: 3 },
            { name: "XL", additional_price: 0, available: true, position: 4 },
            { name: "2XL", additional_price: 2, available: true, position: 5 },
            { name: "3XL", additional_price: 4, available: true, position: 6 }
          ]
        )
        presets << preset
      end
      
      presets
    end
    
    # Get preset statistics
    def get_preset_stats(preset)
      {
        id: preset.id,
        name: preset.name,
        option_count: preset.option_presets.count,
        available_option_count: preset.option_presets.where(available: true).count,
        times_used: count_preset_usage(preset),
        created_at: preset.created_at
      }
    end
    
    private
    
    def count_preset_usage(preset)
      # Count how many times this preset has been applied by looking for option groups
      # with the same name and similar structure
      @restaurant.wholesale_items
                 .joins(:option_groups)
                 .where(wholesale_option_groups: { name: preset.name })
                 .distinct
                 .count
    end
  end
end
