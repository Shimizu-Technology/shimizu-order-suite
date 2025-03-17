class RemoveRestaurantReferenceFromSeatSections < ActiveRecord::Migration[7.2]
  def change
    # If the column is truly gone, do nothing:
    say "restaurant_id column already removed from seat_sections. Skipping."
  end
end
