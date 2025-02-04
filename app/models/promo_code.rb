class PromoCode < ApplicationRecord
  # validations
  validates :code, presence: true, uniqueness: true
  validates :discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  # Example method to check if valid
  def active?
    (valid_from <= Time.now) && (valid_until.nil? || valid_until >= Time.now) &&
      (max_uses.nil? || current_uses < max_uses)
  end
end
