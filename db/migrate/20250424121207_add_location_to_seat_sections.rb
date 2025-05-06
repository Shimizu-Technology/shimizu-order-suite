class AddLocationToSeatSections < ActiveRecord::Migration[7.2]
  def change
    # Make the location field optional initially to support existing records
    add_reference :seat_sections, :location, null: true, foreign_key: true
  end
end
