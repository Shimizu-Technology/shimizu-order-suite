# app/models/menu_item.rb

class MenuItem < ApplicationRecord
  belongs_to :menu
  has_many :option_groups, dependent: :destroy

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :advance_notice_hours, numericality: { greater_than_or_equal_to: 0 }

  # Optionally limit length of promo_label if you like:
  # validates :promo_label, length: { maximum: 50 }, allow_nil: true

  # -------------------------------
  # Validation for Featured
  # -------------------------------
  validate :limit_featured_items, on: [:create, :update]

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

  # -------------------------------------------------------------------------
  # FUTURE-PROOF: Let as_json specify all the fields we want in the API
  # -------------------------------------------------------------------------
  def as_json(options = {})
    super(options).merge(
      'price'                 => price.to_f,
      'image_url'             => image_url,
      'advance_notice_hours'  => advance_notice_hours,
      'seasonal'              => seasonal,
      'available_from'        => available_from,
      'available_until'       => available_until,
      'promo_label'           => promo_label,
      'featured'              => featured  # <--- IMPORTANT
    )
  end

  private

  # -------------------------------
  # Enforce max 4 featured
  # -------------------------------
  def limit_featured_items
    # Only run if we're switching this item to featured (true).
    if featured_changed? && featured?
      # Count existing featured items (excluding this one).
      currently_featured = MenuItem.where(featured: true).where.not(id: self.id).count
      if currently_featured >= 4
        errors.add(:featured, "cannot exceed 4 total featured items.")
      end
    end
  end
end
