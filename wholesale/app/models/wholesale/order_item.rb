# app/models/wholesale/order_item.rb

module Wholesale
  class OrderItem < ApplicationRecord
    # Associations
    belongs_to :order, class_name: 'Wholesale::Order'
    belongs_to :item, class_name: 'Wholesale::Item'
    
    # Validations
    validates :quantity, presence: true, numericality: { greater_than: 0, only_integer: true }
    validates :price_cents, presence: true, numericality: { greater_than: 0 }
    validates :item_name, presence: true
    
    # Custom validations
    validate :item_availability, on: :create
    validate :quantity_available, on: :create
    validate :validate_option_selections, on: :create
    validate :options_availability, on: :create
    
    # Callbacks
    before_validation :snapshot_item_data, if: -> { item.present? && (new_record? || item_id_changed?) }
    before_validation :normalize_selected_options
    before_create :validate_and_reserve_inventory
    
    # Scopes
    scope :by_item, ->(item) { where(item: item) }
    scope :with_quantity, ->(quantity) { where(quantity: quantity) }
    
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
    
    # Calculations
    def line_total_cents
      (quantity || 0) * (price_cents || 0)
    end
    
    def line_total
      line_total_cents / 100.0
    end
    
    def unit_price
      price
    end
    
    def total_price
      line_total
    end
    
    # Item information helpers
    def current_item_name
      item&.name
    end
    
    def current_item_description
      item&.description
    end
    
    def current_item_price
      item&.price
    end
    
    def item_name_changed_since_order?
      item_name != current_item_name
    end
    
    def item_description_changed_since_order?
      item_description != current_item_description
    end
    
    def item_price_changed_since_order?
      price_cents != item&.price_cents
    end
    
    def item_data_stale?
      item_name_changed_since_order? || 
      item_description_changed_since_order? || 
      item_price_changed_since_order?
    end
    
    # Inventory helpers
    def item_tracks_inventory?
      item&.track_inventory?
    end
    
    def sufficient_inventory?
      return true unless item_tracks_inventory?
      item.available_quantity >= quantity
    end
    
    def inventory_impact
      return 0 unless item_tracks_inventory?
      quantity
    end
    
    # Update quantity and recalculate order total
    def update_quantity!(new_quantity)
      return false if new_quantity <= 0
      return true if quantity == new_quantity
      
      old_quantity = quantity
      quantity_diff = new_quantity - old_quantity
      
      # Check inventory if increasing quantity
      if quantity_diff > 0 && item_tracks_inventory?
        return false unless item.available_quantity >= quantity_diff
      end
      
      transaction do
        # Update inventory
        if item_tracks_inventory?
          if quantity_diff > 0
            # Reducing more inventory
            item.reduce_stock!(quantity_diff)
          else
            # Returning inventory
            item.increment!(:stock_quantity, quantity_diff.abs)
          end
        end
        
        # Update quantity
        update!(quantity: new_quantity)
        
        # Recalculate order total
        order.update!(total_cents: order.subtotal_cents)
      end
      
      true
    rescue => e
      Rails.logger.error("Failed to update order item quantity: #{e.message}")
      false
    end
    
    # Remove item from order
    def remove_from_order!
      transaction do
        # Return inventory if tracked
        if item_tracks_inventory?
          item.increment!(:stock_quantity, quantity)
        end
        
        # Remove the item
        destroy!
        
        # Recalculate order total
        order.update!(total_cents: order.subtotal_cents)
      end
    end
    
    # Snapshot current item data for historical record
    def update_snapshot!
      return false unless item.present?
      
      update!(
        item_name: item.name,
        item_description: item.description,
        price_cents: item.price_cents
      )
    end
    
    # Selected options helpers
    def selected_size
      selected_options['size']
    end
    
    def selected_color
      selected_options['color']
    end
    
    def selected_option(key)
      selected_options[key.to_s]
    end
    
    def has_selected_options?
      selected_options.present? && selected_options.any?
    end
    
    def variant_description
      return item_name if selected_options.blank?
      
      # Handle legacy variant system (size/color)
      if selected_options.key?('size') || selected_options.key?('color')
        variant_parts = []
        variant_parts << selected_options['size'] if selected_options['size'].present?
        variant_parts << selected_options['color'] if selected_options['color'].present?
        
        if variant_parts.any?
          return "#{item_name} (#{variant_parts.join(', ')})"
        end
      end
      
      # Handle new option group system
      if item&.has_options?
        return item.option_selection_display_name(selected_options)
      end
      
      item_name
    end
    
    # ===== OPTION GROUP METHODS =====
    
    # Check if this order item uses the new option group system
    def uses_option_groups?
      item&.has_options? && has_option_group_selections?
    end
    
    # Check if selected_options contains option group selections (numeric keys)
    def has_option_group_selections?
      return false unless selected_options.present?
      selected_options.keys.any? { |key| key.to_s.match?(/^\d+$/) }
    end
    
    # Validate option selections against item's option groups
    def validate_option_selections
      return true unless item&.has_options?
      
      validation_errors = item.validate_option_selection(selected_options)
      
      validation_errors.each do |error|
        errors.add(:selected_options, error)
      end
      
      validation_errors.empty?
    end
    
    # Calculate price based on selected options
    def calculate_option_price
      return item.price if item.nil? || !item.has_options?
      
      item.calculate_price_for_options(selected_options)
    end
    
    # Check if the selected options are available for purchase
    def options_available_for_purchase?
      return true unless item&.has_options?
      
      item.can_purchase_with_options?(selected_options, quantity)
    end
    
    private
    
    def snapshot_item_data
      return unless item.present?
      
      self.item_name = item.name
      self.item_description = item.description
      
      # Calculate price based on selected options
      if item.has_options? && selected_options.present?
        calculated_price = calculate_option_price
        self.price_cents = (calculated_price * 100).round
      else
        self.price_cents = item.price_cents
      end
    end
    
    def item_availability
      return unless item.present?
      
      unless item.active?
        errors.add(:item, 'is not available for purchase')
      end
      
      unless item.fundraiser.active?
        errors.add(:item, 'fundraiser is not active')
      end
      
      unless item.fundraiser.current?
        errors.add(:item, 'fundraiser is not currently accepting orders')
      end
    end
    
    def quantity_available
      return unless item.present? && quantity.present?
      
      if item_tracks_inventory? && !item.can_purchase?(quantity)
        available = item.available_quantity
        if available <= 0
          errors.add(:quantity, 'item is out of stock')
        else
          errors.add(:quantity, "only #{available} available (requested #{quantity})")
        end
      end
    end
    
    def validate_and_reserve_inventory
      return true unless item_tracks_inventory?
      
      # This is handled in the Order model's reduce_inventory! method
      # We don't want to double-reduce here, just validate
      unless item.can_purchase?(quantity)
        raise "Insufficient inventory for #{item.name}"
      end
    end
    
    def options_availability
      return unless item.present?
      
      # Check if selected options are available for purchase
      unless options_available_for_purchase?
        errors.add(:selected_options, 'contains unavailable options or invalid selections')
      end
    end
    
    def normalize_selected_options
      self.selected_options = {} if selected_options.nil?
      
      # Remove empty values
      self.selected_options = selected_options.reject { |k, v| v.blank? }
    end
  end
end