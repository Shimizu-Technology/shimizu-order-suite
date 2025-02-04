# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :user, optional: true

  # Example: items is JSON column with line items
  # items: [
  #   { "id": "omg-lumpia", "name": "O.M.G. Lumpia", "quantity": 2, "price": 11.95, "customizations": { ... } },
  #   ...
  # ]

  validates :status, inclusion: { in: %w[pending preparing ready completed cancelled] }

  # Override as_json to convert `total` to float
  def as_json(options = {})
    # Call super to keep default keys (id, created_at, etc.)
    # Then merge a new key "total" => total.to_f
    super(options).merge("total" => total.to_f)
  end
end
