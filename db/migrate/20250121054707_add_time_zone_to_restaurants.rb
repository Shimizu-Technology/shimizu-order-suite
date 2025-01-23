class AddTimeZoneToRestaurants < ActiveRecord::Migration[7.2]
  def change
    add_column :restaurants, :time_zone, :string, default: "Pacific/Guam", null: false
  end
end
