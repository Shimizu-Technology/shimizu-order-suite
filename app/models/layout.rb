# app/models/layout.rb
class Layout < ApplicationRecord
  # Default scope to current restaurant
  default_scope { with_restaurant_scope }
  belongs_to :restaurant
  has_many :seat_sections, dependent: :destroy

  # sections_data is optional, can hold minimal geometry or other layout metadata
  # {
  #   "sections": [
  #     { "id": "temp-123", "offsetX": 100, "offsetY": 200, "orientation": "vertical" },
  #     ...
  #   ]
  # }
end
