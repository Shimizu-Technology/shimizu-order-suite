# app/models/wholesale/item_image.rb

module Wholesale
  class ItemImage < ApplicationRecord
    # Associations
    belongs_to :item, class_name: 'Wholesale::Item'
    
    # Validations
    validates :image_url, presence: true, 
                          format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: 'must be a valid URL' }
    validates :position, presence: true, numericality: { greater_than: 0 }
    validates :position, uniqueness: { scope: :item_id }
    
    # Custom validations
    validate :only_one_primary_per_item
    validate :primary_image_position_should_be_one
    
    # Callbacks
    before_validation :set_default_position, if: -> { position.blank? }
    before_validation :ensure_primary_is_first, if: -> { primary? && position != 1 }
    after_create :set_as_primary_if_first
    after_destroy :reassign_primary_if_needed
    
    # Scopes
    scope :by_position, -> { order(:position) }
    scope :primary, -> { where(primary: true) }
    scope :secondary, -> { where(primary: false) }
    
    # Instance methods
    def primary?
      primary
    end
    
    def secondary?
      !primary?
    end
    
    def make_primary!
      return true if primary?
      
      transaction do
        # Remove primary flag from other images
        item.item_images.where(primary: true).update_all(primary: false)
        
        # Move this image to position 1 and make it primary
        self.class.where(item: item).where('position < ?', position).update_all('position = position + 1')
        update!(position: 1, primary: true)
        
        # Reorder other images
        reorder_positions!
      end
    end
    
    def move_to_position!(new_position)
      return true if position == new_position
      return false if new_position < 1
      
      max_position = item.item_images.maximum(:position) || 1
      new_position = [new_position, max_position].min
      
      transaction do
        if new_position > position
          # Moving down - shift up items in between
          item.item_images.where('position > ? AND position <= ?', position, new_position)
                         .update_all('position = position - 1')
        else
          # Moving up - shift down items in between
          item.item_images.where('position >= ? AND position < ?', new_position, position)
                         .update_all('position = position + 1')
        end
        
        update!(position: new_position)
      end
    end
    
    def reorder_positions!
      item.item_images.order(:position, :id).each_with_index do |img, index|
        img.update_column(:position, index + 1) if img.position != (index + 1)
      end
    end
    
    # File name helper
    def filename
      return nil unless image_url.present?
      File.basename(URI.parse(image_url).path)
    rescue URI::InvalidURIError
      nil
    end
    
    # File extension helper
    def file_extension
      return nil unless filename.present?
      File.extname(filename).downcase.delete('.')
    end
    
    def image_type
      case file_extension
      when 'jpg', 'jpeg'
        'jpeg'
      when 'png'
        'png'
      when 'gif'
        'gif'
      when 'webp'
        'webp'
      else
        'unknown'
      end
    end
    
    private
    
    def set_default_position
      max_position = item&.item_images&.maximum(:position) || 0
      self.position = max_position + 1
    end
    
    def ensure_primary_is_first
      self.position = 1 if primary?
    end
    
    def set_as_primary_if_first
      if item.item_images.count == 1
        update_column(:primary, true)
      end
    end
    
    def reassign_primary_if_needed
      if primary? && item.item_images.any?
        # Make the first image primary
        first_image = item.item_images.order(:position).first
        first_image&.update_column(:primary, true)
      end
    end
    
    def only_one_primary_per_item
      return unless primary?
      
      existing_primary = item&.item_images&.where(primary: true)&.where&.not(id: id)&.exists?
      if existing_primary
        errors.add(:primary, 'only one primary image allowed per item')
      end
    end
    
    def primary_image_position_should_be_one
      if primary? && position != 1
        # Auto-correct instead of erroring - move to position 1
        self.position = 1
      end
    end
  end
end