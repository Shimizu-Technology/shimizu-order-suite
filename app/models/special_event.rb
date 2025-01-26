class SpecialEvent < ApplicationRecord
  belongs_to :restaurant
  validates :event_date, presence: true
  # Optional validations for max_capacity
end
