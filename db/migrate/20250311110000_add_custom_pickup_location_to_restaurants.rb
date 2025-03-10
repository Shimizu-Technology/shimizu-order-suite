class AddCustomPickupLocationToRestaurants < ActiveRecord::Migration[7.2]
  def change
    add_column :restaurants, :custom_pickup_location, :string
  end
end
