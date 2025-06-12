class OptionStockAudit < ApplicationRecord
  belongs_to :option
  belongs_to :user, optional: true
  belongs_to :order, optional: true

  validates :previous_quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :new_quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :reason, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_option, ->(option) { where(option: option) }
  scope :by_user, ->(user) { where(user: user) }

  def quantity_change
    new_quantity - previous_quantity
  end

  def quantity_increased?
    quantity_change > 0
  end

  def quantity_decreased?
    quantity_change < 0
  end
end 