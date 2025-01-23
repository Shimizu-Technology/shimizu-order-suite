# app/models/waitlist_entry.rb
class WaitlistEntry < ApplicationRecord
  belongs_to :restaurant

  # If you want to see which seats are occupied by this waitlist entry:
  has_many :seat_allocations, dependent: :nullify
  has_many :seats, through: :seat_allocations

  # Basic example columns: contact_name, party_size, status, check_in_time, etc.
  # e.g. "waiting", "seated", "removed" ...
  # Add validations as desired:
  # validates :contact_name, presence: true
  # validates :party_size, numericality: { greater_than: 0 }, allow_nil: true

  ############################
  def seat_labels
    seat_allocations
      .where(released_at: nil)
      .includes(:seat)
      .map { |alloc| alloc.seat.label }
  end
  ############################
end
