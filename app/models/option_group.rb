# app/models/option_group.rb
class OptionGroup < ApplicationRecord
  include IndirectTenantScoped
  
  # Define the path to restaurant for tenant isolation
  tenant_path through: [:menu_item, :menu], foreign_key: 'restaurant_id'

  belongs_to :menu_item
  has_many :options, dependent: :destroy

  validates :name, presence: true
  validates :min_select, numericality: { greater_than_or_equal_to: 0 }
  validates :max_select, numericality: { greater_than_or_equal_to: 1 }
  validates :free_option_count, numericality: { greater_than_or_equal_to: 0 }
  validate :free_option_count_not_greater_than_max_select

  def free_option_count_not_greater_than_max_select
    if free_option_count.present? && max_select.present? && free_option_count > max_select
      errors.add(:free_option_count, "cannot be greater than max_select")
    end
  end

  # Note: with_restaurant_scope is now provided by IndirectTenantScoped

  # We remove the as_json override entirely.
  # The controller calls `include: { options: { methods: [:additional_price_float] }}`.
  # That automatically yields JSON for each Option, including that method.
  
  # Check if the option group has any available options
  def has_available_options?
    options.where(is_available: true).exists?
  end
  
  # Check if this is a required group (min_select > 0) with no available options
  def required_but_unavailable?
    min_select > 0 && !has_available_options?
  end
  
  # Include availability status in JSON representation
  def as_json(options = {})
    super(options).tap do |json|
      json['has_available_options'] = has_available_options?
      json['required_but_unavailable'] = required_but_unavailable?
    end
  end
end
