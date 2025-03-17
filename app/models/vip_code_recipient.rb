class VipCodeRecipient < ApplicationRecord
  belongs_to :vip_access_code

  validates :email, presence: true
  validates :sent_at, presence: true

  # Add a default scope to include restaurant scope through the vip_access_code
  default_scope { joins(:vip_access_code).merge(VipAccessCode.with_restaurant_scope) }

  # Scopes for filtering
  scope :by_email, ->(email) { where(email: email) }
  scope :recent, -> { order(sent_at: :desc) }
end
