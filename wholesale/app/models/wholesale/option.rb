module Wholesale
  class Option < ApplicationRecord
    self.table_name = 'wholesale_options'
    
    # Soft delete support
    scope :active, -> { where(deleted_at: nil) }
    scope :deleted, -> { where.not(deleted_at: nil) }
    
    belongs_to :option_group, class_name: 'Wholesale::OptionGroup', foreign_key: 'wholesale_option_group_id'
    
    # Inventory audit trail
    has_many :option_stock_audits, class_name: 'Wholesale::OptionStockAudit', foreign_key: 'wholesale_option_id', dependent: :destroy
    
    validates :name, presence: true
    validates :name, uniqueness: { scope: :wholesale_option_group_id, message: "must be unique within the option group" }
    validates :additional_price, numericality: { greater_than_or_equal_to: 0 }
    validates :position, numericality: { greater_than_or_equal_to: 0 }
    validates :total_ordered, numericality: { greater_than_or_equal_to: 0 }
    validates :total_revenue, numericality: { greater_than_or_equal_to: 0 }
    
    # Future inventory validations (when inventory tracking is enabled)
    validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :damaged_quantity, numericality: { greater_than_or_equal_to: 0 }
    validates :low_stock_threshold, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validate :damaged_quantity_not_greater_than_stock, if: :inventory_tracking_enabled?
    
    scope :available, -> { where(available: true) }
    scope :unavailable, -> { where(available: false) }
    scope :by_position, -> { order(:position) }
    
    # Set default position before creation
    before_create :set_default_position
    
    # Sales tracking methods
    def add_sale!(quantity, revenue)
      increment!(:total_ordered, quantity)
      increment!(:total_revenue, revenue)
    end
    
    # Check if this option has inventory tracking enabled through its option group
    def inventory_tracking_enabled?
      option_group&.inventory_tracking_enabled? || false
    end
    
    # Get available stock for this option (stock - damaged)
    def available_stock
      return nil unless inventory_tracking_enabled?
      return 0 unless stock_quantity.present?
      
      total = stock_quantity.to_i
      damaged = damaged_quantity.to_i
      available = total - damaged
      
      [available, 0].max
    end
    
    # Check if option is in stock (has available stock)
    def in_stock?
      return true unless inventory_tracking_enabled?
      available_stock > 0
    end

    # Check if option is out of stock
    def out_of_stock?
      inventory_tracking_enabled? && available_stock <= 0
    end

    # Check if option is low stock (you can customize the threshold)
    def low_stock?(threshold = 5)
      return false unless inventory_tracking_enabled?
      available_stock <= threshold && available_stock > 0
    end
    
    # Get the low stock threshold for this option
    def actual_low_stock_threshold
      low_stock_threshold || option_group&.wholesale_item&.actual_low_stock_threshold || 5
    end
    
    # Mark a quantity as damaged without affecting stock quantity
    def mark_as_damaged(quantity, reason, user = nil)
      return false unless inventory_tracking_enabled?

      transaction do
        # Create audit record for damaged option
        stock_audit = Wholesale::OptionStockAudit.create_damaged_record(self, quantity, reason, user)

        # Update the damaged quantity
        previous_damaged = self.damaged_quantity || 0
        self.update!(damaged_quantity: previous_damaged + quantity.to_i)

        true
      end
    rescue => e
      Rails.logger.error("Failed to mark wholesale option as damaged: #{e.message}")
      false
    end

    # Update stock quantity with audit trail
    def update_stock_quantity(new_quantity, reason_type, reason_details = nil, user = nil, order = nil)
      return false unless inventory_tracking_enabled?

      transaction do
        # Create audit record
        stock_audit = Wholesale::OptionStockAudit.create_stock_record(self, new_quantity, reason_type, reason_details, user, order)

        # Update the stock quantity
        self.update!(stock_quantity: new_quantity)

        true
      end
    rescue => e
      Rails.logger.error("Failed to update wholesale option stock quantity: #{e.message}")
      false
    end

    # Convenience methods with audit trail
    def restock!(quantity, notes: nil, user: nil)
      return false unless inventory_tracking_enabled?
      
      new_quantity = (stock_quantity || 0) + quantity
      update_stock_quantity(new_quantity, 'restock', notes, user)
    end
    
    def reduce_stock!(quantity, reason: 'manual_adjustment', user: nil, order: nil)
      return true unless inventory_tracking_enabled?
      
      # Check availability with better error messaging
      unless in_stock? && available_stock >= quantity
        available = available_stock
        if available <= 0
          raise "#{full_display_name} is out of stock"
        else
          raise "Insufficient stock for #{full_display_name}. Only #{available} available (requested #{quantity})"
        end
      end
      
      new_quantity = (stock_quantity || 0) - quantity
      success = update_stock_quantity(new_quantity, reason, "Reduced by #{quantity}", user, order)
      
      unless success
        raise "Failed to reduce stock for #{full_display_name}"
      end
      
      success
    end
    
    def set_stock!(quantity, notes: nil, user: nil)
      return false unless inventory_tracking_enabled?
      
      update_stock_quantity(quantity, 'manual_adjustment', notes, user)
    end
    
    # Get the final price including any additional price
    def final_price
      base_price_cents = option_group&.wholesale_item&.price_cents || 0
      base_price = base_price_cents / 100.0
      (base_price + (additional_price || 0)).to_f
    end
    
    # Display methods
    def display_name
      name
    end
    
    def full_display_name
      item_name = option_group&.wholesale_item&.name || "Unknown Item"
      "#{item_name} - #{name}"
    end
    
    # Soft delete methods
    def soft_delete!
      return false if used_in_orders?
      update!(deleted_at: Time.current)
    end
    
    def deleted?
      deleted_at.present?
    end
    
    def restore!
      update!(deleted_at: nil)
    end
    
    # Check if this option is used in any orders
    def used_in_orders?
      # Check if any order items reference this option ID in their selected_options
      Wholesale::OrderItem.joins(:order)
        .where("EXISTS (SELECT 1 FROM jsonb_each(selected_options) AS j(key, value) WHERE value @> :option_id)", option_id: "[#{id}]")
        .exists?
    end
    
    private
    
    def set_default_position
      return if position.present? && position > 0
      
      max_position = option_group&.options&.maximum(:position) || 0
      self.position = max_position + 1
    end
    
    def damaged_quantity_not_greater_than_stock
      return unless stock_quantity.present? && damaged_quantity.present?
      
      if damaged_quantity > stock_quantity
        errors.add(:damaged_quantity, "cannot be greater than stock quantity")
      end
    end
  end
end