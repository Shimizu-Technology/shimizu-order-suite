class AddRestaurantIdToSiteSettings < ActiveRecord::Migration[7.2]
  def change
    add_reference :site_settings, :restaurant, null: true, foreign_key: true
  end
end
