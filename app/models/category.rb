# app/models/category.rb
class Category < ApplicationRecord
  include Broadcastable
  apply_default_scope
  
  # Define which attributes should trigger broadcasts
  broadcasts_on :name, :position

  # Change association from restaurant to menu
  belongs_to :menu
  # Add a method to access restaurant through menu
  has_one :restaurant, through: :menu
  
  has_many :menu_item_categories, dependent: :destroy
  has_many :menu_items, through: :menu_item_categories

  # Update validation to be scoped to menu_id instead of restaurant_id
  validates :name, presence: true, uniqueness: { scope: :menu_id }
  validates :menu_id, presence: true
  
  # Update default scope to use menu's restaurant for tenant isolation
  def self.with_restaurant_scope
    if current_restaurant
      joins(:menu).where(menus: { restaurant_id: current_restaurant.id })
    else
      all
    end
  end
end
