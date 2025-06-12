# app/models/option_group.rb
class OptionGroup < ApplicationRecord
  include IndirectTenantScoped
  
  # Define the path to restaurant for tenant isolation
  tenant_path through: [:menu_item, :menu], foreign_key: 'restaurant_id'

  belongs_to :menu_item
  has_many :options, dependent: :destroy

  validates :name, presence: true
  validates :min_select, numericality: { greater_than_or_equal_to: 0 }
  validates :max_select, numericality: { greater_than_or_equal_to: 1 }
  validates :free_option_count, numericality: { greater_than_or_equal_to: 0 }
  validates :low_stock_threshold, numericality: { greater_than_or_equal_to: 0 }
  validates :tracking_priority, numericality: { greater_than_or_equal_to: 0 }
  validate :free_option_count_not_greater_than_max_select
  validate :validate_option_inventory_constraints

  def free_option_count_not_greater_than_max_select
    if free_option_count.present? && max_select.present? && free_option_count > max_select
      errors.add(:free_option_count, "cannot be greater than max_select")
    end
  end

  def validate_option_inventory_constraints
    # Option inventory can only be enabled for required groups (min_select > 0)
    if enable_option_inventory && min_select == 0
      errors.add(:enable_option_inventory, "can only be enabled for required option groups")
    end
    
    # Only primary tracking (priority = 1) per menu item
    if tracking_priority == 1 && enable_option_inventory
      existing = menu_item.option_groups.where(tracking_priority: 1, enable_option_inventory: true)
                          .where.not(id: id)
      if existing.exists?
        errors.add(:tracking_priority, "can only have one primary tracking group per menu item")
      end
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
  
  # Inventory tracking methods
  def enable_option_inventory?
    enable_option_inventory
  end

  def primary_tracking_group?
    tracking_priority == 1 && enable_option_inventory?
  end

  def total_available_stock
    return 0 unless enable_option_inventory?
    options.sum(&:available_quantity)
  end

  def has_low_stock_options?
    return false unless enable_option_inventory?
    options.any?(&:low_stock?)
  end

  def has_out_of_stock_options?
    return false unless enable_option_inventory?
    options.any?(&:out_of_stock?)
  end

  def all_options_out_of_stock?
    return false unless enable_option_inventory?
    return false if options.empty?
    options.all?(&:out_of_stock?)
  end

  # Check availability considering stock levels
  def has_available_options?
    if enable_option_inventory?
      options.where(is_available: true).any? { |option| !option.out_of_stock? }
    else
      options.where(is_available: true).exists?
    end
  end

  # Include availability status in JSON representation
  def as_json(options = {})
    super(options).tap do |json|
      json['has_available_options'] = has_available_options?
      json['required_but_unavailable'] = required_but_unavailable?
      json['enable_option_inventory'] = enable_option_inventory?
      json['primary_tracking_group'] = primary_tracking_group?
      json['total_available_stock'] = total_available_stock
      json['has_low_stock_options'] = has_low_stock_options?
      json['all_options_out_of_stock'] = all_options_out_of_stock?
    end
  end
end
