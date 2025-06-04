# app/models/option_group.rb
class OptionGroup < ApplicationRecord
  include IndirectTenantScoped
  
  # Define the path to restaurant for tenant isolation
  # Uses a lambda to dynamically determine the appropriate path based on the associated object
  tenant_path lambda { |record|
    # Make sure record is an actual record and not a symbol or other type
    if record.is_a?(OptionGroup) && record.optionable_type.present? && record.optionable_type == 'FundraiserItem'
      { through: [:optionable, :fundraiser], foreign_key: 'restaurant_id', polymorphic: true }
    else
      # Default to menu item path for backward compatibility
      { through: [:menu_item, :menu], foreign_key: 'restaurant_id' }
    end
  }

  # Keep old association for backward compatibility
  belongs_to :menu_item, optional: true
  # Add new polymorphic association
  belongs_to :optionable, polymorphic: true, optional: true
  has_many :options, dependent: :destroy
  
  # Validation to ensure either menu_item or optionable is present
  validate :ensure_valid_association
  
  # Custom validation to ensure we have a valid association
  def ensure_valid_association
    unless menu_item_id.present? || (optionable_id.present? && optionable_type.present?)
      errors.add(:base, "Option group must be associated with either a menu item or another optionable object")
    end
  end

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
