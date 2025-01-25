class AddDurationMinutesToReservations < ActiveRecord::Migration[7.2]
  def change
    add_column :reservations, :duration_minutes, :integer, default: 60
  end
end
