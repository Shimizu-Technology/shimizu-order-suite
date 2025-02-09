class Option < ApplicationRecord
  belongs_to :option_group

  validates :name, presence: true
  validates :additional_price, numericality: { greater_than_or_equal_to: 0.0 }

  # Instead of overriding as_json, we provide a method that returns a float.
  # The controller uses `methods: [:additional_price_float]` to include it.
  def additional_price_float
    additional_price.to_f
  end
end
