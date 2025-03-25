# app/models/menu.rb
class Menu < ApplicationRecord
  # Default scope to current restaurant
  default_scope { with_restaurant_scope }
  belongs_to :restaurant
  has_many :menu_items, dependent: :destroy
  # Add categories association
  has_many :categories, dependent: :destroy

  validates :name, presence: true

  # Ensure we call each MenuItem's as_json override (for numeric price).
  def as_json(options = {})
    data = super(options)
    data["menu_items"] = menu_items.map(&:as_json)
    data
  end
end
