# app/models/category.rb
class Category < ApplicationRecord
  apply_default_scope

  belongs_to :restaurant
  has_many :menu_item_categories, dependent: :destroy
  has_many :menu_items, through: :menu_item_categories

  validates :name, presence: true, uniqueness: { scope: :restaurant_id }
  validates :restaurant_id, presence: true
end
