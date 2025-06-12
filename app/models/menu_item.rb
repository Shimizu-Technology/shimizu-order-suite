# app/models/menu_item.rb

class MenuItem < ApplicationRecord
  # First define the belongs_to association before any has_many :through associations
  belongs_to :menu
  
  # Include IndirectTenantScoped after defining the menu association
  include IndirectTenantScoped
  
  # Define the path to restaurant for tenant isolation
  tenant_path through: :menu, foreign_key: 'restaurant_id'
  
  # Include Broadcastable after defining the associations it depends on
  include Broadcastable
  
  # Define which attributes should trigger broadcasts
  broadcasts_on :name, :price, :description, :stock_quantity, :damaged_quantity, 
               :low_stock_threshold, :enable_stock_tracking, :hidden, :featured

  has_many :option_groups, dependent: :destroy
  has_many :menu_item_stock_audits, dependent: :destroy

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
  
  # Option-level inventory validation
  validate :validate_option_level_inventory_constraints

  # Note: with_restaurant_scope is now provided by IndirectTenantScoped

  # Optional: validation for promo_label length
  # validates :promo_label, length: { maximum: 50 }, allow_nil: true

  # Validation for Featured
  validate :limit_featured_items, on: [ :create, :update ]

  # Inventory strategy helper methods (matching PRD design)
  def option_level_tracking?
    enable_stock_tracking && option_groups.any?(&:enable_option_inventory?)
  end

  def menu_item_level_tracking?
    enable_stock_tracking && !option_level_tracking?
  end

  def manual_tracking?
    !enable_stock_tracking
  end

  def primary_tracked_option_group
    option_groups.find(&:primary_tracking_group?)
  end

  def inventory_tracking_type
    return "manual" if manual_tracking?
    return "option_level" if option_level_tracking?
    return "menu_item_level" if menu_item_level_tracking?
    "manual"
  end

  # Inventory tracking methods
  def available_quantity
    return nil unless enable_stock_tracking

    if option_level_tracking?
      # For option-level tracking, return total available across primary tracked options
      primary_group = primary_tracked_option_group
      return primary_group&.total_available_stock || 0
    else
      # Menu item-level tracking (existing logic)
      total = stock_quantity.to_i
      damaged = damaged_quantity.to_i
      available = total - damaged

      Rails.logger.info("INVENTORY DEBUG: available_quantity for #{id} (#{name}) - Stock: #{total}, Damaged: #{damaged}, Available: #{available}")

      available
    end
  end

  def actual_low_stock_threshold
    low_stock_threshold || 10  # Default to 10 if not set
  end

  # Mark a quantity as damaged without affecting stock quantity
  def mark_as_damaged(quantity, reason, user)
    return false unless enable_stock_tracking

    transaction do
      # Create audit record for damaged item
      stock_audit = MenuItemStockAudit.create_damaged_record(self, quantity, reason, user)

      # Update the damaged quantity
      previous_damaged = self.damaged_quantity || 0
      self.update!(damaged_quantity: previous_damaged + quantity.to_i)

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

  # Update stock status based on available quantity (supports both menu item and option level tracking)
  def update_stock_status!
    return unless enable_stock_tracking

    old_status = stock_status
    
    new_status = if option_level_tracking?
                   # Option-level inventory logic
                   primary_group = primary_tracked_option_group
                   if primary_group&.all_options_out_of_stock?
                     :out_of_stock
                   elsif primary_group&.has_low_stock_options?
                     :low_stock
                   else
                     :in_stock
                   end
                 else
                   # Menu item-level inventory logic (existing)
                   available = available_quantity
                   if available <= 0
                     :out_of_stock
                   elsif available <= actual_low_stock_threshold
                     :low_stock
                   else
                     :in_stock
                   end
                 end

    # Only update if status has changed
    if stock_status != new_status.to_s
      update_column(:stock_status, new_status)
      
      # Broadcast low stock notification if status changed to low_stock
      if new_status == :low_stock && old_status != 'low_stock'
        # Use the WebsocketBroadcastService to broadcast the low stock notification
        WebsocketBroadcastService.broadcast_low_stock(self)
      end
    end
  end

  # Stock status enum & optional note
  enum :stock_status, {
    in_stock: 0,
    out_of_stock: 1,
    low_stock: 2
  }, prefix: true

  scope :currently_available, -> {
    day_of_week = Date.current.wday
    
    where(available: true)
      .where(<<-SQL.squish, today: Date.current)
        (
          (seasonal = FALSE)
          OR (
            seasonal = TRUE
            AND (available_from IS NULL OR available_from <= :today)
            AND (available_until IS NULL OR available_until >= :today)
          )
        )
      SQL
      .where("available_days IS NULL OR available_days = '[]' OR available_days::jsonb ? :day", day: day_of_week.to_s)
  }
  
  # Check if item is available on the current day based on restaurant's time zone
  def available_on_current_day?
    return true if available_days.blank? || available_days.empty?
    
    restaurant_time = Time.current.in_time_zone(restaurant.time_zone)
    current_day = restaurant_time.wday
    
    # Convert available_days to an array of integers if it's not already
    days_array = if available_days.is_a?(Array)
                   available_days.map(&:to_i)
                 else
                   [available_days.to_i]
                 end
    
    days_array.include?(current_day)
  end

  # Check if the menu item has any required option groups with all options unavailable
  def has_required_groups_with_unavailable_options?
    option_groups.any? { |group| group.required_but_unavailable? }
  end
  
  # Get the list of required option groups with all options unavailable
  def required_groups_with_unavailable_options
    option_groups.select { |group| group.required_but_unavailable? }
  end
  
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
      "available_days"       => available_days || [],
      "hidden"               => hidden,
      # Use numeric IDs only:
      "category_ids"         => categories.map(&:id),
      # Add availability information
      "has_required_unavailable_options" => has_required_groups_with_unavailable_options?
    )

    # Add inventory tracking fields if enabled
    if enable_stock_tracking
      result.merge!(
        "enable_stock_tracking" => enable_stock_tracking,
        "inventory_tracking_type" => inventory_tracking_type,
        "available_quantity" => available_quantity
      )
      
      # Add menu item level tracking fields
      if menu_item_level_tracking?
        result.merge!(
          "stock_quantity" => stock_quantity.to_i,
          "damaged_quantity" => damaged_quantity.to_i,
          "low_stock_threshold" => actual_low_stock_threshold
        )
      end
      
      # Add option level tracking information
      if option_level_tracking?
        primary_group = primary_tracked_option_group
        result.merge!(
          "primary_tracked_option_group_id" => primary_group&.id,
          "primary_tracked_option_group_name" => primary_group&.name,
          "total_option_stock" => primary_group&.total_available_stock || 0
        )
      end
    end

    result
  end

  private

  # Validation for option-level inventory constraints
  def validate_option_level_inventory_constraints
    return unless enable_stock_tracking
    
    # If option-level tracking is enabled, cannot have both option and menu item tracking
    primary_groups = option_groups.select(&:primary_tracking_group?)
    if primary_groups.count > 1
      errors.add(:option_groups, "can only have one primary tracked option group")
    end
  end

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

  # Enforce max 4 featured items per menu
  def limit_featured_items
    if featured_changed? && featured?
      # Only count featured items from the same menu
      currently_featured = MenuItem.where(featured: true, menu_id: self.menu_id).where.not(id: self.id).count
      if currently_featured >= 4
        errors.add(:featured, "cannot exceed 4 featured items per menu.")
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
