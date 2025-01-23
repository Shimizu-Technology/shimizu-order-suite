# app/models/seat_allocation.rb
class SeatAllocation < ApplicationRecord
  belongs_to :seat
  belongs_to :reservation, optional: true
  belongs_to :waitlist_entry, optional: true

  # Optional: validate presence of occupant
  # validate :must_have_one_occupant

  # def must_have_one_occupant
  #   if reservation_id.nil? && waitlist_entry_id.nil?
  #     errors.add(:base, "Must have either a reservation or a waitlist entry")
  #   end
  # end

  # Columns now are:
  #  t.datetime :start_time   # when seat allocation begins
  #  t.datetime :end_time     # scheduled time seat frees (expected)
  #  t.datetime :released_at  # actual time occupant left
end
