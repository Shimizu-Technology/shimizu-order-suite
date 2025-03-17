class MerchandiseCollection < ApplicationRecord
  # Default scope to current restaurant
  default_scope { with_restaurant_scope }

  belongs_to :restaurant
  has_many :merchandise_items, dependent: :destroy

  validates :name, presence: true

  # Similar to Menu model
  def as_json(options = {})
    data = super(options)
    data["merchandise_items"] = merchandise_items.map(&:as_json) if options[:include_items]
    data
  end
end
