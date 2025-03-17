class AddLayoutIdToSeatSections < ActiveRecord::Migration[7.2]
  def change
    add_reference :seat_sections, :layout, null: false, foreign_key: true
    # Optionally remove or deprecate :restaurant_id if you no longer need it:
    # remove_column :seat_sections, :restaurant_id, :bigint
  end
end
