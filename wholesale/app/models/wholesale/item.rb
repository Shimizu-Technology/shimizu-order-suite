# app/models/wholesale/item.rb

module Wholesale
  class Item < ApplicationRecord
    # Associations
    belongs_to :fundraiser, class_name: 'Wholesale::Fundraiser'
    has_many :item_images, class_name: 'Wholesale::ItemImage', dependent: :destroy
    has_many :order_items, class_name: 'Wholesale::OrderItem', dependent: :restrict_with_error
    has_many :variants, class_name: 'Wholesale::WholesaleItemVariant', foreign_key: 'wholesale_item_id', dependent: :destroy
    
    # Virtual attribute for custom variant SKUs
    attr_accessor :custom_variant_skus
    
    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :price_cents, presence: true, numericality: { greater_than: 0 }
    validates :sku, uniqueness: { scope: :fundraiser_id }, allow_blank: true
    validates :position, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
    validates :sort_order, numericality: { greater_than_or_equal_to: 0 }
    validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
    validates :low_stock_threshold, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
    
    # Custom validations
    validate :low_stock_threshold_requires_tracking
    validate :stock_quantity_requires_tracking
    
    # Callbacks
    before_save :set_last_restocked_at, if: -> { stock_quantity_changed? && stock_quantity_was.present? && stock_quantity > stock_quantity_was }
    after_save :handle_variant_updates, if: -> { saved_change_to_options? || saved_change_to_sku? || saved_change_to_price_cents? }
    
    # Scopes
    scope :active, -> { where(active: true) }
    scope :inactive, -> { where(active: false) }
    scope :by_position, -> { order(:position, :sort_order, :name) }
    scope :by_sort_order, -> { order(:sort_order, :name) }
    scope :with_inventory_tracking, -> { where(track_inventory: true) }
    scope :without_inventory_tracking, -> { where(track_inventory: false) }
    scope :low_stock, -> { where(track_inventory: true).where('stock_quantity <= low_stock_threshold AND low_stock_threshold IS NOT NULL') }
    scope :out_of_stock, -> { where(track_inventory: true, stock_quantity: 0) }
    scope :unlimited_stock, -> { where(track_inventory: false) }
    scope :in_stock, -> { where('track_inventory = false OR (track_inventory = true AND stock_quantity > 0)') }
    
    # Price handling (in cents)
    def price
      (price_cents || 0) / 100.0
    end
    
    def price=(amount)
      if amount.is_a?(String)
        self.price_cents = (amount.to_f * 100).round
      else
        self.price_cents = (amount.to_f * 100).round
      end
    end
    
    # Inventory methods
    def track_inventory?
      track_inventory
    end
    
    def unlimited_stock?
      !track_inventory?
    end
    
    def in_stock?(quantity = 1)
      return true if unlimited_stock?
      stock_quantity >= quantity
    end
    
    def out_of_stock?
      track_inventory? && stock_quantity <= 0
    end
    
    def low_stock?
      return false unless track_inventory? && low_stock_threshold.present?
      stock_quantity <= low_stock_threshold
    end
    
    def available_quantity
      return Float::INFINITY unless track_inventory?
      [stock_quantity, 0].max
    end
    
    def stock_status
      return 'unlimited' if unlimited_stock?
      return 'out_of_stock' if out_of_stock?
      return 'low_stock' if low_stock?
      'in_stock'
    end
    
    def can_purchase?(quantity = 1)
      return true if unlimited_stock?
      return true if allow_sale_with_no_stock? && track_inventory?
      quantity <= available_quantity
    end
    
    # Inventory management
    def restock!(quantity, notes: nil)
      return false unless track_inventory?
      
      self.stock_quantity = (stock_quantity || 0) + quantity
      self.last_restocked_at = Time.current
      self.admin_notes = [admin_notes, "Restocked +#{quantity} on #{Time.current.strftime('%m/%d/%Y')}#{notes ? ": #{notes}" : ''}"].compact.join("\n")
      save!
    end
    
    def reduce_stock!(quantity)
      return true if unlimited_stock?
      return false unless in_stock?(quantity)
      
      self.stock_quantity -= quantity
      save!
    end
    
    def set_stock!(quantity, notes: nil)
      return false unless track_inventory?
      
      old_quantity = stock_quantity || 0
      self.stock_quantity = quantity
      self.last_restocked_at = Time.current if quantity > old_quantity
      self.admin_notes = [admin_notes, "Stock set to #{quantity} on #{Time.current.strftime('%m/%d/%Y')}#{notes ? ": #{notes}" : ''}"].compact.join("\n")
      save!
    end
    
    # Image helpers
    def primary_image
      item_images.find_by(primary: true) || item_images.order(:position).first
    end
    
    def primary_image_url
      primary_image&.image_url
    end
    
    def all_image_urls
      item_images.order(:position).pluck(:image_url)
    end
    
    # Order statistics
    def total_ordered_quantity
      # All orders count as revenue since orders can only be created after payment
      order_items.joins(:order).sum(:quantity)
    end
    
    def total_revenue_cents
      # All orders count as revenue since orders can only be created after payment
      order_items.joins(:order).sum('quantity * price_cents')
    end
    
    # Variant management methods (public)
    def has_variants?
      return false unless options.is_a?(Hash)
      size_options = options['size_options'] || []
      color_options = options['color_options'] || []
      size_options.any? || color_options.any?
    end
    
    # Find variant by selected options
    def find_variant_by_options(selected_options)
      return nil unless has_variants? && selected_options.present?
      
      size = selected_options['size'] || selected_options[:size]
      color = selected_options['color'] || selected_options[:color]
      
      variants.find_by(size: size, color: color)
    end
    
    private
    
    def low_stock_threshold_requires_tracking
      if low_stock_threshold.present? && !track_inventory?
        errors.add(:low_stock_threshold, 'can only be set when inventory tracking is enabled')
      end
    end
    
    def stock_quantity_requires_tracking
      if stock_quantity.present? && !track_inventory?
        errors.add(:stock_quantity, 'can only be set when inventory tracking is enabled')
      end
    end
    
    def set_last_restocked_at
      self.last_restocked_at = Time.current
    end
    
    def handle_variant_updates
      # Parse custom_variant_skus if it's a JSON string
      parsed_custom_skus = nil
      if custom_variant_skus.present?
        parsed_custom_skus = custom_variant_skus.is_a?(String) ? JSON.parse(custom_variant_skus) : custom_variant_skus
      end
      
      create_or_update_variants(parsed_custom_skus)
    end
    
    def create_or_update_variants(custom_skus = nil)
      return unless has_variants?
      
      # Get current variant combinations
      current_variants = generate_variant_combinations(custom_skus)
      
      # Remove variants that no longer exist
      if current_variants.any?
        # Build conditions to keep variants that match current combinations
        keep_conditions = current_variants.map do |v|
          if v[:size].present? && v[:color].present?
            "(size = '#{v[:size]}' AND color = '#{v[:color]}')"
          elsif v[:size].present?
            "(size = '#{v[:size]}' AND color IS NULL)"
          elsif v[:color].present?
            "(color = '#{v[:color]}' AND size IS NULL)"
          end
        end.compact.join(' OR ')
        
        variants.where.not(keep_conditions).destroy_all if keep_conditions.present?
      else
        # No variants should exist, remove all
        variants.destroy_all
      end
      
      # Create or update variants
      current_variants.each do |variant_data|
        variant = variants.find_or_initialize_by(
          size: variant_data[:size],
          color: variant_data[:color]
        )
        
        variant.sku = variant_data[:sku]
        variant.price_adjustment = 0.0 # Default, can be customized later
        variant.active = true
        
        # For new variants, inherit stock settings from parent item
        if variant.new_record?
          variant.stock_quantity = track_inventory? ? (stock_quantity || 0) : 0
          variant.low_stock_threshold = low_stock_threshold || 5
          variant.total_ordered = 0
          variant.total_revenue = 0.0
        end
        
        variant.save!
      end
    end
    
    def generate_variant_combinations(custom_skus = nil)
      return [] unless has_variants?
      
      size_options = options['size_options'] || []
      color_options = options['color_options'] || []
      base_sku = sku.present? ? sku.upcase : "ITEM-#{id}"
      
      combinations = []
      index = 0
      
      if size_options.any? && color_options.any?
        # Both sizes and colors - create all combinations
        color_options.each do |color|
          size_options.each do |size|
            custom_sku = custom_skus&.dig(index.to_s) || custom_skus&.dig(index)
            combinations << {
              size: size,
              color: color,
              sku: custom_sku || generate_variant_sku(base_sku, color, size)
            }
            index += 1
          end
        end
      elsif size_options.any?
        # Only sizes
        size_options.each do |size|
          custom_sku = custom_skus&.dig(index.to_s) || custom_skus&.dig(index)
          combinations << {
            size: size,
            color: nil,
            sku: custom_sku || generate_variant_sku(base_sku, nil, size)
          }
          index += 1
        end
      elsif color_options.any?
        # Only colors
        color_options.each do |color|
          custom_sku = custom_skus&.dig(index.to_s) || custom_skus&.dig(index)
          combinations << {
            size: nil,
            color: color,
            sku: custom_sku || generate_variant_sku(base_sku, color, nil)
          }
          index += 1
        end
      end
      
      combinations
    end
    
    def generate_variant_sku(base_sku, color, size)
      parts = [base_sku]
      
      if color.present?
        color_code = color.gsub(/\s+/, '').upcase[0, 3]
        parts << color_code
      end
      
      if size.present?
        size_code = size.gsub(/\s+/, '').upcase
        parts << size_code
      end
      
      parts.join('-')
    end
  end
end