# app/models/category.rb
class Category < ApplicationRecord
  has_many :menu_item_categories, dependent: :destroy
  has_many :menu_items, through: :menu_item_categories

  validates :name, presence: true, uniqueness: true
end
