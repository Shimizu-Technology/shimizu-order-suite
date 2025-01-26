# db/migrate/20250127000002_remove_old_fields_from_restaurants.rb
class RemoveOldFieldsFromRestaurants < ActiveRecord::Migration[7.0]
  def change
    remove_column :restaurants, :opening_time, :time
    remove_column :restaurants, :closing_time, :time
  end
end
