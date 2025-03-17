class OptionGroup < ApplicationRecord
  apply_default_scope

  belongs_to :menu_item
  has_many :options, dependent: :destroy
  # Define path to restaurant through associations for tenant isolation
  has_one :menu, through: :menu_item
  has_one :restaurant, through: :menu

  validates :name, presence: true
  validates :min_select, numericality: { greater_than_or_equal_to: 0 }
  validates :max_select, numericality: { greater_than_or_equal_to: 0 }

  # Override with_restaurant_scope for indirect restaurant association
  def self.with_restaurant_scope
    if current_restaurant
      joins(menu_item: :menu).where(menus: { restaurant_id: current_restaurant.id })
    else
      all
    end
  end

  # We remove the as_json override entirely.
  # The controller calls `include: { options: { methods: [:additional_price_float] }}`.
  # That automatically yields JSON for each Option, including that method.
end
