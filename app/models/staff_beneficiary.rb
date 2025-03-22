class StaffBeneficiary < ApplicationRecord
  belongs_to :restaurant
  has_many :staff_discounts
  
  validates :name, presence: true, uniqueness: { scope: :restaurant_id }
  
  scope :active, -> { where(active: true) }
end
