class StaffDiscountConfiguration < ApplicationRecord
  belongs_to :restaurant
  
  validates :name, presence: true, length: { maximum: 100 }
  validates :code, presence: true, 
                   length: { maximum: 50 },
                   format: { with: /\A[a-z0-9_]+\z/, message: "can only contain lowercase letters, numbers, and underscores" },
                   uniqueness: { scope: :restaurant_id }
  validates :discount_percentage, presence: true, 
                                  numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :discount_type, presence: true, inclusion: { in: %w[percentage fixed_amount] }
  validates :display_order, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :ui_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "must be a valid hex color" }, allow_blank: true

  scope :active, -> { where(is_active: true) }
  scope :ordered, -> { order(:display_order, :name) }
  scope :defaults, -> { where(is_default: true) }

  before_save :ensure_single_default_per_restaurant
  before_validation :sanitize_code

  # Calculate the actual discount amount for a given total
  def calculate_discount(total)
    return 0 if total.nil? || total.zero?
    
    case discount_type
    when 'percentage'
      (total * (discount_percentage / 100.0)).round(2)
    when 'fixed_amount'
      [discount_percentage, total].min.round(2)  # Can't discount more than the total
    else
      0
    end
  end

  # Calculate the final amount after discount
  def calculate_final_amount(total)
    return 0 if total.nil? || total.zero?
    
    discount_amount = calculate_discount(total)
    (total - discount_amount).round(2)
  end

  # Get the discount rate as a decimal (for percentage discounts)
  def discount_rate
    return 0 unless discount_type == 'percentage'
    discount_percentage / 100.0
  end

  # Display label for UI
  def display_label
    case discount_type
    when 'percentage'
      if discount_percentage.zero?
        name
      else
        "#{name} (#{discount_percentage.to_i}% off)"
      end
    when 'fixed_amount'
      "#{name} ($#{discount_percentage} off)"
    else
      name
    end
  end

  # JSON representation for API responses
  def to_api_hash
    {
      id: id,
      name: name,
      code: code,
      discount_percentage: discount_percentage,
      discount_type: discount_type,
      is_active: is_active,
      is_default: is_default,
      display_order: display_order,
      description: description,
      ui_color: ui_color,
      display_label: display_label
    }
  end

  private

  def ensure_single_default_per_restaurant
    if is_default && restaurant_id.present?
      # Remove default flag from other configurations in the same restaurant
      self.class.where(restaurant_id: restaurant_id, is_default: true)
                .where.not(id: id)
                .update_all(is_default: false)
    end
  end

  def sanitize_code
    if code.present?
      self.code = code.strip.downcase.gsub(/[^a-z0-9_]/, '_').squeeze('_')
    end
  end
end 