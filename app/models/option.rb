# app/models/option.rb
class Option < ApplicationRecord
  apply_default_scope

  belongs_to :option_group
  # Define path to restaurant through associations for tenant isolation
  has_one :menu_item, through: :option_group
  has_one :menu, through: :menu_item
  has_one :restaurant, through: :menu

  validates :name, presence: true
  validates :additional_price, numericality: { greater_than_or_equal_to: 0.0 }
  validates :is_preselected, inclusion: { in: [true, false] }

  # Override with_restaurant_scope for indirect restaurant association
  def self.with_restaurant_scope
    if current_restaurant
      joins(option_group: { menu_item: :menu }).where(menus: { restaurant_id: current_restaurant.id })
    else
      all
    end
  end

  # Instead of overriding as_json, we provide a method that returns a float.
  # The controller uses `methods: [:additional_price_float]` to include it.
  def additional_price_float
    additional_price.to_f
  end
end
