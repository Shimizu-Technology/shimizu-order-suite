# app/models/menu_item.rb

class MenuItem < ApplicationRecord
  belongs_to :menu
  has_many :option_groups, dependent: :destroy

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :advance_notice_hours, numericality: { greater_than_or_equal_to: 0 }

  # Optionally limit length of promo_label if you like:
  # validates :promo_label, length: { maximum: 50 }, allow_nil: true

  scope :currently_available, -> {
    where(available: true)
      .where(<<-SQL.squish, today: Date.current)
        (seasonal = FALSE)
        OR (
          seasonal = TRUE
          AND (available_from IS NULL OR available_from <= :today)
          AND (available_until IS NULL OR available_until >= :today)
        )
      SQL
  }

  # Override as_json so we get floating price + extra fields
  def as_json(options = {})
    super(options).merge(
      'price' => price.to_f,
      'image_url' => image_url,
      'advance_notice_hours' => advance_notice_hours,
      'seasonal' => seasonal,
      'available_from' => available_from,
      'available_until' => available_until,
      'promo_label' => promo_label
    )
  end
end
