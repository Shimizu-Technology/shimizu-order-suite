# app/models/menu_item.rb
class MenuItem < ApplicationRecord
  belongs_to :menu

  # Optional: If you have an inventory_status table linking to a menu_item, do:
  # has_one :inventory_status, dependent: :destroy

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
end
