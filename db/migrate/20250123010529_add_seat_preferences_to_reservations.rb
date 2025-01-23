class AddSeatPreferencesToReservations < ActiveRecord::Migration[7.2]
  def change
    add_column :reservations, :seat_preferences, :jsonb, default: [], null: false
  end
end
