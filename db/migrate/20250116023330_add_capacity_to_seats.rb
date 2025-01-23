# db/migrate/20250116000000_add_capacity_to_seats.rb
class AddCapacityToSeats < ActiveRecord::Migration[7.2]
  def change
    add_column :seats, :capacity, :integer, default: 1, null: false
  end
end
