# app/models/menu_item.rb

class MenuItem < ApplicationRecord
  apply_default_scope

  belongs_to :menu
  has_many :option_groups, dependent: :destroy
  has_many :menu_item_stock_audits, dependent: :destroy
  # Define path to restaurant through associations for tenant isolation
  has_one :restaurant, through: :menu

  # Callback to reset inventory fields when tracking is disabled
  before_save :reset_inventory_fields_if_tracking_disabled

  # Many-to-many categories
  has_many :menu_item_categories, dependent: :destroy
  has_many :categories, through: :menu_item_categories

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :advance_notice_hours, numericality: { greater_than_or_equal_to: 0 }
  validate :must_have_at_least_one_category, on: [ :create, :update ]

  # Inventory tracking validations
  validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :damaged_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :low_stock_threshold, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true

  # Override with_restaurant_scope for indirect restaurant association
  def self.with_restaurant_scope
    if current_restaurant
      joins(:menu).where(menus: { restaurant_id: current_restaurant.id })
    else
      all
    end
  end

  # Optional: validation for promo_label length
  # validates :promo_label, length: { maximum: 50 }, allow_nil: true

  # Validation for Featured
  validate :limit_featured_items, on: [ :create, :update ]

  # Inventory tracking methods
  def available_quantity
    return nil unless enable_stock_tracking

    total = stock_quantity.to_i
    damaged = damaged_quantity.to_i
    available = total - damaged

    Rails.logger.info("INVENTORY DEBUG: available_quantity for #{id} (#{name}) - Stock: #{total}, Damaged: #{damaged}, Available: #{available}")

    available
  end

  def actual_low_stock_threshold
    low_stock_threshold || 10  # Default to 10 if not set
  end

  # Mark a quantity as damaged and decrease stock quantity
  def mark_as_damaged(quantity, reason, user)
    return false unless enable_stock_tracking

    transaction do
      # Create audit record for damaged item
      stock_audit = MenuItemStockAudit.create_damaged_record(self, quantity, reason, user)

      # Update the damaged quantity
      previous_damaged = self.damaged_quantity || 0
      self.update!(damaged_quantity: previous_damaged + quantity.to_i)

      # Also decrease the stock quantity
      previous_stock = self.stock_quantity || 0
      new_stock = [ previous_stock - quantity.to_i, 0 ].max

      # Create stock adjustment record
      stock_audit = MenuItemStockAudit.create_stock_record(
        self,
        new_stock,
        "damaged",
        "Damaged: #{reason}",
        user
      )

      # Update stock
      self.update!(stock_quantity: new_stock)

      # Re-evaluate stock status based on available quantity
      update_stock_status!

      true
    end
  rescue => e
    Rails.logger.error("Failed to mark item as damaged: #{e.message}")
    false
  end

  # Only increment damaged quantity without changing available quantity (for order edits)
  def increment_damaged_only(quantity, reason, user)
    return false unless enable_stock_tracking

    # Add debug logging
    Rails.logger.info("INVENTORY DEBUG: Before increment_damaged_only - Item #{id} (#{name}) - Stock: #{stock_quantity}, Damaged: #{damaged_quantity}, Available: #{available_quantity}")

    transaction do
      # Create audit record
      stock_audit = MenuItemStockAudit.create_damaged_record(self, quantity, reason, user)

      # Update the damaged quantity
      previous_damaged = self.damaged_quantity || 0

      # IMPORTANT: Also increment the stock quantity by the same amount
      # This ensures that available_quantity (stock - damaged) remains the same
      previous_stock = self.stock_quantity || 0

      # Update both quantities
      self.update!(
        damaged_quantity: previous_damaged + quantity.to_i,
        stock_quantity: previous_stock + quantity.to_i
      )

      # Create a stock adjustment audit record to track the stock increase
      stock_audit = MenuItemStockAudit.create_stock_record(
        self,
        previous_stock + quantity.to_i,
        "adjustment",
        "Stock adjusted to match damaged items from order",
        user
      )

      # DO NOT re-evaluate stock status - these items are already
      # removed from inventory, we're just tracking if they're damaged

      # Log after update
      Rails.logger.info("INVENTORY DEBUG: After increment_damaged_only - Item #{id} (#{name}) - Stock: #{stock_quantity}, Damaged: #{damaged_quantity}, Available: #{available_quantity}")

      true
    end
  rescue => e
    Rails.logger.error("Failed to mark item as damaged: #{e.message}")
    false
  end

  # Update stock quantity
  def update_stock_quantity(new_quantity, reason_type, reason_details = nil, user = nil, order = nil)
    return false unless enable_stock_tracking

    transaction do
      # Create audit record
      stock_audit = MenuItemStockAudit.create_stock_record(self, new_quantity, reason_type, reason_details, user, order)

      # Update the stock quantity
      self.update!(stock_quantity: new_quantity)

      # Re-evaluate stock status based on available quantity
      update_stock_status!

      true
    end
  rescue => e
    Rails.logger.error("Failed to update stock quantity: #{e.message}")
    false
  end

  # Update stock status based on available quantity
  def update_stock_status!
    return unless enable_stock_tracking

    available = available_quantity

    new_status = if available <= 0
                  :out_of_stock
    elsif available <= actual_low_stock_threshold
                  :low_stock
    else
                  :in_stock
    end

    update_column(:stock_status, stock_status_before_type_cast) unless stock_status == new_status.to_s
  end

  # Stock status enum & optional note
  enum :stock_status, {
    in_stock: 0,
    out_of_stock: 1,
    low_stock: 2
  }, prefix: true

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

  # as_json => only expose category_ids, not full objects
  def as_json(options = {})
    result = super(options).merge(
      "price"                => price.to_f,
      "cost_to_make"         => cost_to_make.to_f,
      "image_url"            => image_url,
      "advance_notice_hours" => advance_notice_hours,
      "seasonal"             => seasonal,
      "available_from"       => available_from,
      "available_until"      => available_until,
      "promo_label"          => promo_label,
      "featured"             => featured,
      "stock_status"         => stock_status,
      "status_note"          => status_note,
      # Use numeric IDs only:
      "category_ids"         => categories.map(&:id)
    )

    # Add inventory tracking fields if enabled
    if enable_stock_tracking
      result.merge!(
        "enable_stock_tracking" => enable_stock_tracking,
        "stock_quantity" => stock_quantity.to_i,
        "damaged_quantity" => damaged_quantity.to_i,
        "available_quantity" => available_quantity,
        "low_stock_threshold" => actual_low_stock_threshold
      )
    end

    result
  end

  private

  # Reset inventory tracking fields when tracking is turned off
  def reset_inventory_fields_if_tracking_disabled
    if enable_stock_tracking_changed? && !enable_stock_tracking
      # Set inventory fields to NULL in the database
      self.stock_quantity = nil
      self.damaged_quantity = nil
      self.low_stock_threshold = nil

      # Also ensure stock status is not based on inventory
      self.stock_status = "in_stock" unless stock_status_changed?
    end
  end

  # Enforce max 4 featured items
  def limit_featured_items
    if featured_changed? && featured?
      currently_featured = MenuItem.where(featured: true).where.not(id: self.id).count
      if currently_featured >= 4
        errors.add(:featured, "cannot exceed 4 total featured items.")
      end
    end
  end

  # Ensure menu item belongs to at least one category
  def must_have_at_least_one_category
    if categories.empty? && category_ids.blank?
      errors.add(:base, "Menu item must be assigned to at least one category")
    end
  end
end
