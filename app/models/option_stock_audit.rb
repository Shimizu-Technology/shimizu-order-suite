class OptionStockAudit < ApplicationRecord
  include IndirectTenantScoped
  
  # Define the path to restaurant for tenant isolation (through option -> option_group -> menu_item -> menu)
  tenant_path through: [:option, :option_group, :menu_item, :menu], foreign_key: 'restaurant_id'

  belongs_to :option
  belongs_to :user, optional: true
  belongs_to :order, optional: true

  validates :previous_quantity, :new_quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Predefined reason categories
  REASONS = {
    damaged: "Damaged",
    sale: "Sale",
    restock: "Restock",
    adjustment: "Inventory Adjustment",
    other: "Other"
  }.freeze

  # Get quantity change (positive for increases, negative for decreases)
  def quantity_change
    new_quantity - previous_quantity
  end

  # Helper method to create a damaged option audit
  def self.create_damaged_record(option, quantity, reason_details, user)
    return unless option.option_group&.inventory_tracking_enabled?

    previous = option.damaged_quantity || 0
    new_damaged = previous + quantity.to_i

    create!(
      option: option,
      previous_quantity: previous,
      new_quantity: new_damaged,
      reason: "#{REASONS[:damaged]}: #{reason_details} (#{option.name})",
      user: user
    )
  end

  # Helper method to create a stock quantity update audit
  def self.create_stock_record(option, new_stock, reason_type, reason_details = nil, user = nil, order = nil)
    return unless option.option_group&.inventory_tracking_enabled?

    previous = option.stock_quantity || 0

    full_reason = if reason_details.present?
                    "#{REASONS[reason_type.to_sym]}: #{reason_details}"
                  else
                    REASONS[reason_type.to_sym]
                  end

    create!(
      option: option,
      previous_quantity: previous,
      new_quantity: new_stock,
      reason: full_reason,
      user: user,
      order: order
    )
  end
end
