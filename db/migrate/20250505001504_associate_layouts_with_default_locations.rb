class AssociateLayoutsWithDefaultLocations < ActiveRecord::Migration[7.2]
  def up
    # This migration associates existing layouts with default locations
    say_with_time "Associating existing layouts with default locations" do
      migrated_count = 0
      error_count = 0
      
      # Find all restaurants with layouts
      restaurants_with_layouts = Restaurant.joins(:layouts).distinct
      
      restaurants_with_layouts.find_each do |restaurant|
        # Find the default location for this restaurant
        default_location = restaurant.locations.find_by(is_default: true)
        
        if default_location.nil?
          # If no default location exists, find the first location
          default_location = restaurant.locations.first
        end
        
        if default_location.present?
          # Update all layouts for this restaurant to use the default location
          layouts_to_update = restaurant.layouts.where(location_id: nil)
          
          if layouts_to_update.update_all(location_id: default_location.id)
            count = layouts_to_update.count
            migrated_count += count
            say "Associated #{count} layouts for restaurant '#{restaurant.name}' with location '#{default_location.name}'"
          else
            error_count += 1
            say "Error updating layouts for restaurant '#{restaurant.name}'"
          end
        else
          error_count += 1
          say "No locations found for restaurant '#{restaurant.name}' - skipping #{restaurant.layouts.count} layouts"
        end
      end
      
      say "Successfully associated #{migrated_count} layouts with default locations"
      say "Encountered errors for #{error_count} restaurants"
      
      migrated_count
    end
  end

  def down
    # This migration is not reversible as it would require knowing which layouts
    # had null location_id values before the migration
    say "This migration cannot be reversed"
  end
end
