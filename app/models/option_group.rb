class OptionGroup < ApplicationRecord
  belongs_to :menu_item
  has_many :options, dependent: :destroy

  validates :name, presence: true
  validates :min_select, numericality: { greater_than_or_equal_to: 0 }
  validates :max_select, numericality: { greater_than_or_equal_to: 0 }

  # We remove the as_json override entirely.
  # The controller calls `include: { options: { methods: [:additional_price_float] }}`.
  # That automatically yields JSON for each Option, including that method.
end
