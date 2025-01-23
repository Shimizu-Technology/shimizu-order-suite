# db/migrate/20250120000000_add_check_constraint_for_seats.rb
class AddCheckConstraintForSeats < ActiveRecord::Migration[7.2]
  def up
    # Remove or update any seats with unknown statuses
    # For example, set all nil statuses to 'free' so the check constraint won’t fail:
    Seat.where(status: nil).update_all(status: "free")

    execute <<~SQL
      ALTER TABLE seats
      ADD CONSTRAINT check_seat_status
      CHECK (status IN ('free', 'occupied', 'reserved'));
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE seats
      DROP CONSTRAINT check_seat_status;
    SQL
  end
end
