# db/migrate/20250116000000_add_waitlist_entry_id_to_seat_allocations.rb
class AddWaitlistEntryIdToSeatAllocations < ActiveRecord::Migration[7.0]
  def change
    add_reference :seat_allocations, :waitlist_entry, foreign_key: true, null: true
  end
end
