class MenuItem < ApplicationRecord
  belongs_to :menu
  has_many :option_groups, dependent: :destroy

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }

  # We can keep this small override if you want the top-level price to be a float
  # and ensure 'image_url' is always present in the JSON (not strictly required).
  def as_json(options = {})
    super(options).merge(
      'price' => price.to_f,
      'image_url' => image_url
    )
  end
end
