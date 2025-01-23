class RemoveRestaurantIdFromSeatSections < ActiveRecord::Migration[7.2]
  def change
    remove_reference :seat_sections, :restaurant, foreign_key: true, null: false
    # or if you prefer the long-form:
    # remove_column :seat_sections, :restaurant_id, :bigint
  end
end