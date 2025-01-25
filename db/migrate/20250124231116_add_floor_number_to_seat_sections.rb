class AddFloorNumberToSeatSections < ActiveRecord::Migration[7.2]
  def change
    # You can store an integer floor_number (e.g. 1, 2, 3) 
    # or a string floor_label ("1st Floor", "Rooftop").
    # Here, we choose an integer with a default of 1.
    add_column :seat_sections, :floor_number, :integer, default: 1, null: false
  end
end
