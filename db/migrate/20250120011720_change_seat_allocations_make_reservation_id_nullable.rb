class ChangeSeatAllocationsMakeReservationIdNullable < ActiveRecord::Migration[7.2]
  def change
    change_column_null :seat_allocations, :reservation_id, true
  end
end