class RemoveOpeningHoursFromRestaurants < ActiveRecord::Migration[7.2]
  def change
    remove_column :restaurants, :opening_hours, :string
  end
end
