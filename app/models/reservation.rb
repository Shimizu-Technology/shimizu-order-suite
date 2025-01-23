# app/models/reservation.rb
class Reservation < ApplicationRecord
  belongs_to :restaurant
  has_many :seat_allocations, dependent: :nullify
  has_many :seats, through: :seat_allocations

  validates :restaurant_id, presence: true
  validates :start_time, presence: true
  validates :party_size,
            presence: true,
            numericality: { greater_than: 0 }
  validates :contact_name, presence: true

  before_validation :default_status, on: :create

  private

  def default_status
    self.status = 'booked' if status.blank?
  end
end
