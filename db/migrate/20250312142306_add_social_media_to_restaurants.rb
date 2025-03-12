class AddSocialMediaToRestaurants < ActiveRecord::Migration[7.2]
  def change
    add_column :restaurants, :facebook_url, :string
    add_column :restaurants, :instagram_url, :string
    add_column :restaurants, :twitter_url, :string
  end
end
