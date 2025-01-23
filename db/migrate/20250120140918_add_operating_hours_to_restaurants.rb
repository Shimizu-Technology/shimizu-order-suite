# db/migrate/20250122000000_add_operating_times_to_restaurants.rb
class AddOperatingHoursToRestaurants < ActiveRecord::Migration[7.2]
  def change
    add_column :restaurants, :opening_time, :time
    add_column :restaurants, :closing_time, :time
    add_column :restaurants, :time_slot_interval, :integer, default: 30
  end
end
