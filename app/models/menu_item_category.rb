# app/models/menu_item_category.rb
class MenuItemCategory < ApplicationRecord
  belongs_to :menu_item
  belongs_to :category
end
