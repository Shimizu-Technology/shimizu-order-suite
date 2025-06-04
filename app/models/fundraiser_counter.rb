class FundraiserCounter < ApplicationRecord
  include TenantScoped
  
  # Associations
  belongs_to :restaurant
  belongs_to :fundraiser
  
  # Validations
  validates :counter_value, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :restaurant_id, presence: true
  validates :fundraiser_id, presence: true, uniqueness: { scope: :restaurant_id }
end
