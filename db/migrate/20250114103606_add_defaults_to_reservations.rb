class AddDefaultsToReservations < ActiveRecord::Migration[7.2]
  def change
    change_column_default :reservations, :party_size, 1
    change_column_default :reservations, :status, 'booked'
    change_column_default :reservations, :reservation_source, 'online'
  end
end
