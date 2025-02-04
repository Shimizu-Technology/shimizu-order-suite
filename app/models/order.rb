# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :user, optional: true  # e.g. if “guest checkout” is allowed
  
  # JSON array of line items in `items` field:
  #   [
  #     { "id": "omg-lumpia", "name": "O.M.G. Lumpia", "quantity": 2, "price": 11.95, "customizations": { ... } },
  #     ...
  #   ]
  #
  # Alternatively, you could create an `order_items` join table, but storing
  # items in JSON is simpler for now.

  validates :status, inclusion: { in: %w[pending preparing ready completed cancelled] }

  # Helper to sum up total if you want to ensure total is consistent with line items:
  # def recalc_total
  #   sum = items.sum { |item| item['price'].to_f * item['quantity'].to_i }
  #   update!(total: sum)
  # end
end
