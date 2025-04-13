# app/models/option.rb
class Option < ApplicationRecord
  include IndirectTenantScoped
  
  # Define the path to restaurant for tenant isolation
  tenant_path through: [:option_group, :menu_item, :menu], foreign_key: 'restaurant_id'

  belongs_to :option_group

  validates :name, presence: true
  validates :additional_price, numericality: { greater_than_or_equal_to: 0.0 }
  validates :is_preselected, inclusion: { in: [true, false] }
  validates :is_available, inclusion: { in: [true, false] }

  # Note: with_restaurant_scope is now provided by IndirectTenantScoped

  # Instead of overriding as_json, we provide a method that returns a float.
  # The controller uses `methods: [:additional_price_float]` to include it.
  def additional_price_float
    additional_price.to_f
  end
  
  # Override as_json to include the is_available field
  def as_json(options = {})
    super(options).tap do |json|
      json['additional_price_float'] = additional_price_float
      json['is_available'] = is_available
    end
  end
end
