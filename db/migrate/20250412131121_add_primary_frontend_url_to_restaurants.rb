class AddPrimaryFrontendUrlToRestaurants < ActiveRecord::Migration[7.2]
  def change
    add_column :restaurants, :primary_frontend_url, :string
  end
end
