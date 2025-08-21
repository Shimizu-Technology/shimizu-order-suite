module Wholesale
  class OptionGroupPreset < ApplicationRecord
    self.table_name = 'wholesale_option_group_presets'
    
    # Associations
    belongs_to :restaurant
    has_many :option_presets, class_name: 'Wholesale::OptionPreset', 
             foreign_key: 'wholesale_option_group_preset_id', dependent: :destroy
    
    # Validations
    validates :name, presence: true
    validates :name, uniqueness: { scope: :restaurant_id, message: "must be unique within the restaurant" }
    validates :min_select, numericality: { greater_than_or_equal_to: 0 }
    validates :max_select, numericality: { greater_than_or_equal_to: 1 }
    validate :max_select_greater_than_min_select
    
    # Scopes
    scope :by_position, -> { order(:position, :name) }
    scope :required, -> { where(required: true) }
    scope :optional, -> { where(required: false) }
    
    # Callbacks
    before_create :set_default_position
    
    # Instance methods
    def has_available_options?
      option_presets.where(available: true).exists?
    end
    
    def required_but_unavailable?
      required? && !has_available_options?
    end
    
    def inventory_tracking_enabled?
      enable_inventory_tracking == true
    end
    
    # Apply this preset to create option groups for a specific item
    def apply_to_item!(item)
      # Create the option group
      option_group = item.option_groups.create!(
        name: name,
        min_select: min_select,
        max_select: max_select,
        required: required,
        position: position,
        enable_inventory_tracking: enable_inventory_tracking
      )
      
      # Create the options
      option_presets.order(:position).each do |option_preset|
        option_group.options.create!(
          name: option_preset.name,
          additional_price: option_preset.additional_price,
          available: option_preset.available,
          position: option_preset.position
        )
      end
      
      option_group
    end
    
    # Create a copy of this preset with all its options
    def duplicate!(new_name = nil)
      new_preset = dup
      new_preset.name = new_name || "#{name} (Copy)"
      new_preset.position = self.class.where(restaurant: restaurant).maximum(:position).to_i + 1
      new_preset.save!
      
      # Copy all option presets
      option_presets.order(:position).each do |option_preset|
        new_preset.option_presets.create!(
          name: option_preset.name,
          additional_price: option_preset.additional_price,
          available: option_preset.available,
          position: option_preset.position
        )
      end
      
      new_preset
    end
    
    private
    
    def set_default_position
      return if position.present? && position > 0
      
      max_position = restaurant.wholesale_option_group_presets.maximum(:position) || 0
      self.position = max_position + 1
    end
    
    def max_select_greater_than_min_select
      return unless min_select.present? && max_select.present?
      
      if max_select < min_select
        errors.add(:max_select, "must be greater than or equal to min_select")
      end
    end
  end
end
