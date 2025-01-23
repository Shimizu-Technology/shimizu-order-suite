class MakeSeatLabelNotNull < ActiveRecord::Migration[7.2]
  def change
    change_column_null :seats, :label, false, "Seat"
    # If desired, also add a default: "Seat"
  end
end
