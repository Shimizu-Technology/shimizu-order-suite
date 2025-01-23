class RenameAllocatedAtAndAddEndTimeInSeatAllocations < ActiveRecord::Migration[7.2]
  def change
    # 1) rename_column table, old_name, new_name
    rename_column :seat_allocations, :allocated_at, :start_time

    # 2) add_column :seat_allocations, :end_time, :datetime
    add_column :seat_allocations, :end_time, :datetime
  end
end
