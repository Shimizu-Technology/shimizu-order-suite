# app/models/option_group.rb
class OptionGroup < ApplicationRecord
  include IndirectTenantScoped
  include Broadcastable
  
  # Define the path to restaurant for tenant isolation
  tenant_path through: [:menu_item, :menu], foreign_key: 'restaurant_id'

  # Configure which attributes should trigger broadcasts
  broadcasts_on :enable_inventory_tracking

  belongs_to :menu_item
  has_many :options, dependent: :destroy

  validates :name, presence: true
  validates :min_select, numericality: { greater_than_or_equal_to: 0 }
  validates :max_select, numericality: { greater_than_or_equal_to: 1 }
  validates :free_option_count, numericality: { greater_than_or_equal_to: 0 }
  validate :free_option_count_not_greater_than_max_select
  validate :inventory_tracking_menu_item_validation
  validate :only_one_option_group_can_track_inventory
  validate :option_inventory_totals_match_menu_item, if: :should_validate_option_inventory_sync?

  def free_option_count_not_greater_than_max_select
    if free_option_count.present? && max_select.present? && free_option_count > max_select
      errors.add(:free_option_count, "cannot be greater than max_select")
    end
  end

  # Validation: Only option groups for menu items with inventory tracking can enable option-level tracking
  def inventory_tracking_menu_item_validation
    if enable_inventory_tracking && menu_item && !menu_item.enable_stock_tracking
      errors.add(:enable_inventory_tracking, "can only be enabled for menu items with stock tracking enabled")
    end
  end

  # Validation: Only one option group per menu item can have inventory tracking enabled
  def only_one_option_group_can_track_inventory
    if enable_inventory_tracking && menu_item
      other_tracking_groups = menu_item.option_groups.where(enable_inventory_tracking: true)
      other_tracking_groups = other_tracking_groups.where.not(id: id) if persisted?
      
      if other_tracking_groups.exists?
        errors.add(:enable_inventory_tracking, "only one option group per menu item can have inventory tracking enabled")
      end
    end
  end

  # Validation: Option inventory totals must match menu item inventory
  def option_inventory_totals_match_menu_item
    return unless menu_item&.enable_stock_tracking
    return unless menu_item.stock_quantity.present?
    
    total_option_stock = options.sum(:stock_quantity)
    menu_item_stock = menu_item.stock_quantity.to_i
    
    if total_option_stock != menu_item_stock
      errors.add(:base, "Total option inventory (#{total_option_stock}) must equal menu item inventory (#{menu_item_stock})")
    end
  end

  # Note: with_restaurant_scope is now provided by IndirectTenantScoped

  # We remove the as_json override entirely.
  # The controller calls `include: { options: { methods: [:additional_price_float] }}`.
  # That automatically yields JSON for each Option, including that method.
  
  # Check if the option group has any available options
  def has_available_options?
    options.where(is_available: true).exists?
  end
  
  # Check if this is a required group (min_select > 0) with no available options
  def required_but_unavailable?
    min_select > 0 && !has_available_options?
  end

  # Check if this option group has inventory tracking enabled
  def inventory_tracking_enabled?
    enable_inventory_tracking == true
  end

  # Helper method to determine if we should validate option inventory synchronization
  def should_validate_option_inventory_sync?
    # Only validate if tracking is enabled
    return false unless inventory_tracking_enabled?
    
    # Skip validation if we're enabling tracking for the first time (options haven't been initialized yet)
    if enable_inventory_tracking_changed? && enable_inventory_tracking && !enable_inventory_tracking_was
      return false # Allow the first-time enable to pass, stock will be initialized after save
    end
    
    true
  end

  # Get total stock across all options in this group
  def total_option_stock
    return 0 unless inventory_tracking_enabled?
    options.sum(:stock_quantity)
  end

  # Get available stock across all options in this group (stock - damaged)
  def available_option_stock
    return 0 unless inventory_tracking_enabled?
    options.sum('stock_quantity - damaged_quantity')
  end

  # Check if option group has any options with stock
  def has_option_stock?
    return false unless inventory_tracking_enabled?
    available_option_stock > 0
  end
  
  # Include availability status in JSON representation
  def as_json(options = {})
    super(options).tap do |json|
      json['has_available_options'] = has_available_options?
      json['required_but_unavailable'] = required_but_unavailable?
      json['inventory_tracking_enabled'] = inventory_tracking_enabled?
      
      if inventory_tracking_enabled?
        json['total_option_stock'] = total_option_stock
        json['available_option_stock'] = available_option_stock
        json['has_option_stock'] = has_option_stock?
      end
    end
  end

  # Reset all option quantities in this group (used when menu item tracking is toggled)
  def reset_quantities(reason)
    Rails.logger.info("Resetting all option quantities for group #{id} (#{name}): #{reason}")
    
    # Create audit records before resetting (to document the reset)
    options.each do |option|
      # Only create audit if there was actually some inventory to reset
      if option.stock_quantity.to_i > 0 || option.damaged_quantity.to_i > 0
        OptionStockAudit.create_stock_record(
          option,
          0,
          "adjustment",
          reason,
          nil
        )
      end
    end
    
    # Reset all options in this group to 0 quantities
    options.update_all(stock_quantity: 0, damaged_quantity: 0)
    
    Rails.logger.info("Reset #{options.count} options to 0 quantities in group #{id}")
  end
end
