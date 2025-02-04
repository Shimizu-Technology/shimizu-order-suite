# app/models/menu_item.rb
class MenuItem < ApplicationRecord
  belongs_to :menu
  # no has_one_attached

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }

  # If you want to keep a custom JSON shape:
  def as_json(options = {})
    super(options).merge(
      'price' => price.to_f,
      'image_url' => image_url
    )
  end
end
