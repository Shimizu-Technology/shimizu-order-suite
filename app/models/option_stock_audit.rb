class OptionStockAudit < ApplicationRecord
  belongs_to :option
  belongs_to :user, optional: true
  belongs_to :order, optional: true

  REASONS = {
    restock: "Restocked inventory",
    order: "Order placed",
    damaged: "Marked as damaged",
    adjustment: "Manual adjustment",
    return: "Returned to inventory"
  }.freeze

  def self.create_stock_record(option, new_stock, reason_type, reason_details = nil, user = nil, order = nil)
    return unless option.enable_stock_tracking

    previous = option.stock_quantity || 0
    full_reason = reason_details.present? ? "#{REASONS[reason_type.to_sym]}: #{reason_details}" : REASONS[reason_type.to_sym]

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
