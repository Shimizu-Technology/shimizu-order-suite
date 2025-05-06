# app/models/layout.rb
class Layout < ApplicationRecord
  # Default scope to current restaurant
  default_scope { with_restaurant_scope }
  belongs_to :restaurant
  belongs_to :location, optional: true
  has_many :seat_sections, dependent: :destroy

  # Valid shape types for tables
  VALID_TABLE_SHAPES = %w[circle rectangle].freeze
  
  # Valid rotation angles in degrees
  VALID_ROTATIONS = [0, 90, 180, 270].freeze
  
  # sections_data is optional, can hold minimal geometry or other layout metadata
  # {
  #   "sections": [
  #     { "id": "temp-123", "offsetX": 100, "offsetY": 200, "orientation": "vertical" },
  #     # Enhanced with shape, dimensions, and rotation:
  #     { "id": "temp-124", "offsetX": 150, "offsetY": 250, "shape": "rectangle", 
  #       "dimensions": { "width": 120, "height": 80 }, "rotation": 90 },
  #     ...
  #   ]
  # }
  
  # Validate sections_data structure
  validate :validate_sections_data
  
  private
  
  # Validate the shape, dimensions, and rotation properties in sections_data
  def validate_sections_data
    return unless sections_data.present? && sections_data.is_a?(Hash)
    return unless sections_data['sections'].is_a?(Array)
    
    sections_data['sections'].each_with_index do |section, index|
      # Skip if this section doesn't have the enhanced properties
      next unless section.is_a?(Hash)
      
      # Validate shape
      if section['shape'].present? && !VALID_TABLE_SHAPES.include?(section['shape'])
        errors.add(:sections_data, "Section #{index+1} has invalid shape: #{section['shape']}. Valid shapes are: #{VALID_TABLE_SHAPES.join(', ')}")
      end
      
      # Validate rotation
      if section['rotation'].present?
        rotation = section['rotation'].to_i
        unless VALID_ROTATIONS.include?(rotation)
          errors.add(:sections_data, "Section #{index+1} has invalid rotation: #{rotation}. Valid rotations are: #{VALID_ROTATIONS.join(', ')}")
        end
      end
      
      # Validate dimensions for rectangular tables
      if section['shape'] == 'rectangle' && section['dimensions'].present?
        dims = section['dimensions']
        
        if !dims.is_a?(Hash) || !dims['width'].is_a?(Numeric) || !dims['height'].is_a?(Numeric)
          errors.add(:sections_data, "Section #{index+1} has invalid dimensions structure. Must have numeric width and height.")
        elsif dims['width'] <= 0 || dims['height'] <= 0
          errors.add(:sections_data, "Section #{index+1} dimensions must be positive numbers")
        elsif dims['width'] > 500 || dims['height'] > 500
          errors.add(:sections_data, "Section #{index+1} dimensions exceed maximum allowed (500)")
        end
      end
    end
  end
end
