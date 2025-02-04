# app/models/menu.rb
class Menu < ApplicationRecord
  belongs_to :restaurant
  has_many :menu_items, dependent: :destroy

  # Ensure we call each MenuItem's as_json override (for numeric price).
  def as_json(options = {})
    data = super(options)
    data["menu_items"] = menu_items.map(&:as_json)
    data
  end
end
