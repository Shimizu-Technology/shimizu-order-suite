# db/migrate/20250120000001_add_check_constraint_for_reservations.rb
class AddCheckConstraintForReservations < ActiveRecord::Migration[7.2]
  def up
    # Fix any unknown or nil statuses to "booked"
    Reservation.where(status: nil).update_all(status: "booked")

    execute <<~SQL
      ALTER TABLE reservations
      ADD CONSTRAINT check_reservation_status
      CHECK (
        status IN (
          'booked',
          'reserved',
          'seated',
          'finished',
          'canceled',
          'no_show'
        )
      );
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE reservations
      DROP CONSTRAINT check_reservation_status;
    SQL
  end
end
