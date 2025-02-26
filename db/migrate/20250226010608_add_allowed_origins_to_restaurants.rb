class AddAllowedOriginsToRestaurants < ActiveRecord::Migration[7.2]
  def change
    add_column :restaurants, :allowed_origins, :string, array: true, default: []
  end
end
