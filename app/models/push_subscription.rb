class PushSubscription < ApplicationRecord
  belongs_to :restaurant
  
  validates :endpoint, presence: true, uniqueness: { scope: :restaurant_id }
  validates :p256dh_key, presence: true
  validates :auth_key, presence: true
  
  scope :active, -> { where(active: true) }
  
  # Mark subscription as inactive
  def deactivate!
    update(active: false)
  end
end
