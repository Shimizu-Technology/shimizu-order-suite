class PromoCode < ApplicationRecord
  apply_default_scope
  
  # associations
  belongs_to :restaurant
  
  # validations
  validates :code, presence: true, uniqueness: { scope: :restaurant_id }
  validates :discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :restaurant_id, presence: true

  # Example method to check if valid
  def active?
    (valid_from <= Time.now) && (valid_until.nil? || valid_until >= Time.now) &&
      (max_uses.nil? || current_uses < max_uses)
  end
end
