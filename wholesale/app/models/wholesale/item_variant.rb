module Wholesale
  class ItemVariant < ApplicationRecord
    self.table_name = 'wholesale_item_variants'
    
    # Associations
    belongs_to :wholesale_item, class_name: 'Wholesale::Item', foreign_key: 'wholesale_item_id'
    
    # Audit trail
    has_many :variant_stock_audits, class_name: 'Wholesale::VariantStockAudit', foreign_key: 'wholesale_item_variant_id', dependent: :destroy
    
    # Validations
    validates :variant_key, presence: true
    validates :variant_name, presence: true
    validates :variant_key, uniqueness: { scope: :wholesale_item_id, message: "must be unique within the item" }
    validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }
    validates :damaged_quantity, numericality: { greater_than_or_equal_to: 0 }
    validates :low_stock_threshold, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validate :damaged_quantity_not_greater_than_stock
    
    # Scopes
    scope :active, -> { where(active: true) }
    scope :inactive, -> { where(active: false) }
    scope :in_stock, -> { where('stock_quantity > damaged_quantity') }
    scope :out_of_stock, -> { where('stock_quantity <= damaged_quantity') }
    scope :low_stock, -> { where('stock_quantity - damaged_quantity <= low_stock_threshold AND low_stock_threshold IS NOT NULL') }
    
    # Stock calculation methods
    def available_stock
      [stock_quantity - damaged_quantity, 0].max
    end
    
    def out_of_stock?
      available_stock <= 0
    end
    
    def in_stock?(quantity = 1)
      available_stock >= quantity
    end
    
    def low_stock?
      return false unless low_stock_threshold.present?
      available_stock <= low_stock_threshold
    end
    
    # Stock status for display
    def stock_status
      return 'out_of_stock' if out_of_stock?
      return 'low_stock' if low_stock?
      'in_stock'
    end
    
    # Display methods
    def display_name
      variant_name.presence || "#{size} #{color}".strip.presence || "Variant #{id}"
    end
    
    def stock_display
      case stock_status
      when 'out_of_stock'
        "❌ Out of stock"
      when 'low_stock'
        "⚠️ Only #{available_stock} left"
      else
        "✅ #{available_stock} available"
      end
    end
    
    # Legacy support for existing size/color structure
    def legacy_variant_key
      return nil unless size.present? || color.present?
      [size, color].compact.join('-').downcase
    end
    
    # Update stock with validation
    def update_stock!(new_quantity, reason: 'manual_adjustment', user: nil, order: nil)
      old_quantity = stock_quantity || 0
      
      transaction do
        update!(stock_quantity: new_quantity)
        
        # Create audit record
        Wholesale::VariantStockAudit.create_stock_record(
          self, new_quantity, reason, nil, user, order, old_quantity
        )
        
        true
      end
    rescue => e
      Rails.logger.error("Failed to update variant stock: #{e.message}")
      false
    end
    
    # Convenience methods with audit trail
    def restock!(quantity, reason: 'restock', notes: nil, user: nil)
      return false if quantity <= 0
      
      new_quantity = (stock_quantity || 0) + quantity
      update_stock_quantity(new_quantity, reason, notes, user)
    end
    
    def update_stock_quantity(new_quantity, reason, reason_details = nil, user = nil, order = nil)
      return false unless wholesale_item.track_variants?
      
      old_quantity = stock_quantity || 0
      transaction do
        update!(stock_quantity: new_quantity)
        Wholesale::VariantStockAudit.create_stock_record(
          self, new_quantity, reason, reason_details, user, order, old_quantity
        )
        true
      end
    rescue => e
      Rails.logger.error("Failed to update variant stock: #{e.message}")
      false
    end
    
    def reduce_stock!(quantity, reason: 'manual_adjustment', notes: nil, user: nil, order: nil)
      return false if quantity <= 0
      return false if available_stock < quantity
      
      new_quantity = (stock_quantity || 0) - quantity
      update_stock_quantity(new_quantity, reason, notes, user, order)
    end
    
    def mark_damaged!(quantity, reason: 'damaged_goods', notes: nil, user: nil)
      return false if quantity <= 0
      return false if (damaged_quantity || 0) + quantity > stock_quantity
      
      transaction do
        old_damaged = damaged_quantity || 0
        new_damaged = old_damaged + quantity
        update!(damaged_quantity: new_damaged)
        
        # Create audit record
        Wholesale::VariantStockAudit.create_damaged_record(
          self, quantity, "#{reason}#{notes ? ": #{notes}" : ''}", user
        )
        
        true
      end
    rescue => e
      Rails.logger.error("Failed to mark variant as damaged: #{e.message}")
      false
    end
    
    def toggle_active!(user: nil)
      transaction do
        old_status = active?
        new_status = !old_status
        update!(active: new_status)
        
        # Create audit record
        Wholesale::VariantStockAudit.create_status_change_record(
          self, old_status, new_status, user
        )
        
        true
      end
    rescue => e
      Rails.logger.error("Failed to toggle variant status: #{e.message}")
      false
    end
    
    # Audit trail helpers
    def recent_audits(limit = 10)
      variant_stock_audits.recent.limit(limit)
    end
    
    def audit_summary
      {
        total_audits: variant_stock_audits.count,
        stock_updates: variant_stock_audits.by_type('stock_update').count,
        order_events: variant_stock_audits.where(audit_type: %w[order_placed order_cancelled]).count,
        admin_actions: variant_stock_audits.where(audit_type: %w[stock_update damaged restock manual_adjustment status_change]).count,
        last_activity: variant_stock_audits.recent.first&.created_at
      }
    end
    
    private
    
    def damaged_quantity_not_greater_than_stock
      return unless stock_quantity.present? && damaged_quantity.present?
      
      if damaged_quantity > stock_quantity
        errors.add(:damaged_quantity, "cannot be greater than stock quantity")
      end
    end
  end
end
