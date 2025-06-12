# app/models/option.rb
class Option < ApplicationRecord
  include IndirectTenantScoped
  
  # Define the path to restaurant for tenant isolation
  tenant_path through: [:option_group, :menu_item, :menu], foreign_key: 'restaurant_id'

  belongs_to :option_group
  has_many :option_stock_audits, dependent: :destroy
  
  # Default scope to order by position
  default_scope { order(position: :asc) }

  validates :name, presence: true
  validates :additional_price, numericality: { greater_than_or_equal_to: 0.0 }
  validates :is_preselected, inclusion: { in: [true, false] }
  validates :is_available, inclusion: { in: [true, false] }
  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :damaged_quantity, numericality: { greater_than_or_equal_to: 0 }

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
      json['available_quantity'] = available_quantity
      json['is_low_stock'] = low_stock?
      json['is_out_of_stock'] = out_of_stock?
    end
  end

  # Inventory methods
  def available_quantity
    [stock_quantity - damaged_quantity, 0].max
  end

  def low_stock?
    return false unless option_group.enable_option_inventory?
    available_quantity <= option_group.low_stock_threshold
  end

  def out_of_stock?
    return false unless option_group.enable_option_inventory?
    available_quantity <= 0
  end

  def stock_sufficient?(quantity_requested)
    return true unless option_group.enable_option_inventory?
    available_quantity >= quantity_requested
  end

  def update_stock_with_audit!(new_quantity, reason, user: nil, order: nil)
    return unless option_group.enable_option_inventory?
    
    previous_quantity = stock_quantity
    
    transaction do
      update!(stock_quantity: new_quantity)
      
      option_stock_audits.create!(
        previous_quantity: previous_quantity,
        new_quantity: new_quantity,
        reason: reason,
        user: user,
        order: order
      )
    end
  end

  def deduct_stock!(quantity, order: nil)
    return unless option_group.enable_option_inventory?
    
    new_quantity = [stock_quantity - quantity, 0].max
    update_stock_with_audit!(
      new_quantity,
      "Stock deducted for order (#{quantity} units)",
      order: order
    )
  end

  def restore_stock!(quantity, reason = "Stock restored", user: nil, order: nil)
    return unless option_group.enable_option_inventory?
    
    new_quantity = stock_quantity + quantity
    update_stock_with_audit!(new_quantity, reason, user: user, order: order)
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
