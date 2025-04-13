# app/models/option.rb
class Option < ApplicationRecord
  include IndirectTenantScoped
  
  # Define the path to restaurant for tenant isolation
  tenant_path through: [:option_group, :menu_item, :menu], foreign_key: 'restaurant_id'

  belongs_to :option_group
  
  # Default scope to order by position
  default_scope { order(position: :asc) }

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
  
  # Override as_json to include the is_available field and position
  def as_json(options = {})
    super(options).tap do |json|
      json['additional_price_float'] = additional_price_float
      json['is_available'] = is_available
      json['position'] = position
    end
  end
  
  # Set default position when creating a new option
  before_create :set_default_position
  
  # Rebalance positions after deletion
  after_destroy :rebalance_positions
  
  private
  
  def set_default_position
    # If position is not set, set it to the last position in the group + 1
    if position.nil? || position.zero?
      max_position = option_group.options.maximum(:position) || 0
      self.position = max_position + 1
    end
  end
  
  def rebalance_positions
    # Get all remaining options in this group and rebalance their positions
    remaining_options = option_group.options.where.not(id: id).order(:position)
    
    # Update positions to ensure no gaps
    remaining_options.each_with_index do |option, index|
      option.update_column(:position, index + 1)
    end
  end
end
