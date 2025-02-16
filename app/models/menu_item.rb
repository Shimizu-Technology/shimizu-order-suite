# app/models/menu_item.rb

class MenuItem < ApplicationRecord
  belongs_to :menu
  has_many :option_groups, dependent: :destroy

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :advance_notice_hours, numericality: { greater_than_or_equal_to: 0 }

  # If you limit length of promo_label:
  # validates :promo_label, length: { maximum: 50 }, allow_nil: true

  # -------------------------------
  # Validation for Featured
  # -------------------------------
  validate :limit_featured_items, on: [:create, :update]

  # -------------------------------
  # Stock status enum & optional note
  # -------------------------------
  enum stock_status: {
    in_stock: 0,
    out_of_stock: 1,
    low_stock: 2  # <-- renamed from :limited to :low_stock
  }, _prefix: true

  # scope :currently_available => existing logic
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
  # FUTURE-PROOF: as_json to specify extra fields (including stock_status)
  # -------------------------------------------------------------------------
  def as_json(options = {})
    super(options).merge(
      'price'                => price.to_f,
      'image_url'            => image_url,
      'advance_notice_hours' => advance_notice_hours,
      'seasonal'             => seasonal,
      'available_from'       => available_from,
      'available_until'      => available_until,
      'promo_label'          => promo_label,
      'featured'             => featured,
      'stock_status'         => stock_status,   # <-- renamed enum
      'status_note'          => status_note
    )
  end

  private

  # -------------------------------
  # Enforce max 4 featured items
  # -------------------------------
  def limit_featured_items
    if featured_changed? && featured?
      currently_featured = MenuItem.where(featured: true).where.not(id: self.id).count
      if currently_featured >= 4
        errors.add(:featured, "cannot exceed 4 total featured items.")
      end
    end
  end
end
