module Wholesale
  class OptionPreset < ApplicationRecord
    self.table_name = 'wholesale_option_presets'
    
    # Associations
    belongs_to :option_group_preset, class_name: 'Wholesale::OptionGroupPreset', 
               foreign_key: 'wholesale_option_group_preset_id'
    
    # Validations
    validates :name, presence: true
    validates :name, uniqueness: { 
      scope: :wholesale_option_group_preset_id, 
      message: "must be unique within the option group preset" 
    }
    validates :additional_price, numericality: { greater_than_or_equal_to: 0 }
    validates :position, numericality: { greater_than_or_equal_to: 0 }
    
    # Scopes
    scope :available, -> { where(available: true) }
    scope :unavailable, -> { where(available: false) }
    scope :by_position, -> { order(:position, :name) }
    
    # Callbacks
    before_create :set_default_position
    
    # Instance methods
    def display_name
      name
    end
    
    def full_display_name
      group_name = option_group_preset&.name || "Unknown Group"
      "#{group_name} - #{name}"
    end
    
    # Get the restaurant through the option group preset
    def restaurant
      option_group_preset&.restaurant
    end
    
    private
    
    def set_default_position
      return if position.present? && position > 0
      
      max_position = option_group_preset&.option_presets&.maximum(:position) || 0
      self.position = max_position + 1
    end
  end
end
