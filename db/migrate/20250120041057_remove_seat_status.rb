class RemoveSeatStatus < ActiveRecord::Migration[7.2]
  def change
    # First remove the check constraint (named "check_seat_status")
    remove_check_constraint :seats, name: "check_seat_status"

    # Now remove the status column
    remove_column :seats, :status, :string
  end
end
