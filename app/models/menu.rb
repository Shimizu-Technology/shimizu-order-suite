# app/models/menu.rb
class Menu < ApplicationRecord
  include Broadcastable
  include TenantScoped
  
  # Define which attributes should trigger broadcasts
  broadcasts_on :name, :active
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
