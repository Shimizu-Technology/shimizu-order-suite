# app/models/wholesale/order.rb

module Wholesale
  class Order < ApplicationRecord
    include TenantScoped
    
    # Order status constants
    STATUS_PENDING = "pending"
    STATUS_PROCESSING = "processing"
    STATUS_PAID = "paid"
    STATUS_READY = "ready"
    STATUS_SHIPPED = "shipped"
    STATUS_DELIVERED = "delivered"
    STATUS_FULFILLED = "fulfilled"
    STATUS_COMPLETED = "completed"
    STATUS_CANCELLED = "cancelled"
    STATUS_REFUNDED = "refunded"
    
    # Associations
    belongs_to :fundraiser, class_name: 'Wholesale::Fundraiser'
    belongs_to :user, optional: true # Allow guest checkout
    belongs_to :participant, class_name: 'Wholesale::Participant', optional: true
    has_many :order_items, class_name: 'Wholesale::OrderItem', dependent: :destroy
    has_many :order_payments, class_name: 'Wholesale::OrderPayment', dependent: :destroy
    has_many :items, through: :order_items, class_name: 'Wholesale::Item'
    
    # Validations
    validates :order_number, presence: true, uniqueness: { scope: :restaurant_id }
    validates :customer_name, presence: true, length: { maximum: 255 }
    validates :customer_email, presence: true, 
                              format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :total_cents, presence: true, numericality: { greater_than: 0 }
    validates :status, presence: true, inclusion: { in: [
      STATUS_PENDING, STATUS_PROCESSING, STATUS_PAID, STATUS_READY, STATUS_SHIPPED,
      STATUS_DELIVERED, STATUS_FULFILLED, STATUS_COMPLETED, STATUS_CANCELLED, STATUS_REFUNDED
    ]}
    
    # Callbacks
    before_create :assign_order_number
    after_update :update_participant_progress, if: -> { saved_change_to_status? && (paid_or_completed? || fulfilled?) }
    after_update :restore_inventory_on_cancellation, if: -> { saved_change_to_status? && status == STATUS_CANCELLED }
    
    # Scopes
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { where(status: STATUS_PENDING) }
    scope :processing, -> { where(status: STATUS_PROCESSING) }
    scope :paid, -> { where(status: STATUS_PAID) }
    scope :ready, -> { where(status: STATUS_READY) }
    scope :shipped, -> { where(status: STATUS_SHIPPED) }
    scope :delivered, -> { where(status: STATUS_DELIVERED) }
    scope :fulfilled, -> { where(status: STATUS_FULFILLED) }
    scope :completed, -> { where(status: STATUS_COMPLETED) }
    scope :cancelled, -> { where(status: STATUS_CANCELLED) }
    scope :refunded, -> { where(status: STATUS_REFUNDED) }
    scope :paid_or_completed, -> { where(status: [STATUS_PAID, STATUS_COMPLETED]) }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_participant, ->(participant) { where(participant: participant) }
    scope :general_fundraiser, -> { where(participant_id: nil) }
    
    # Total handling (in cents)
    def total
      (total_cents || 0) / 100.0
    end
    
    def total=(amount)
      if amount.is_a?(String)
        self.total_cents = (amount.to_f * 100).round
      else
        self.total_cents = (amount.to_f * 100).round
      end
    end
    
    # Status helpers
    def pending?
      status == STATUS_PENDING
    end
    
    def processing?
      status == STATUS_PROCESSING
    end
    
    def paid?
      status == STATUS_PAID
    end
    
    def ready?
      status == STATUS_READY
    end
    
    def shipped?
      status == STATUS_SHIPPED
    end
    
    def delivered?
      status == STATUS_DELIVERED
    end
    
    def completed?
      status == STATUS_COMPLETED
    end
    
    def fulfilled?
      status == STATUS_FULFILLED
    end
    
    def cancelled?
      status == STATUS_CANCELLED
    end
    
    def refunded?
      status == STATUS_REFUNDED
    end
    
    def paid_or_completed?
      paid? || completed?
    end
    
    def can_be_cancelled?
      pending? || processing?
    end
    
    def can_be_refunded?
      paid? || shipped? || delivered? || completed?
    end
    
    def can_be_shipped?
      paid?
    end
    
    # Order calculations
    def subtotal_cents
      order_items.sum { |item| item.quantity * item.price_cents }
    end
    
    def subtotal
      subtotal_cents / 100.0
    end
    
    def item_count
      order_items.sum(:quantity)
    end
    
    def unique_item_count
      order_items.count
    end
    
    # Payment helpers
    def total_paid_cents
      order_payments.where(status: 'completed').sum(:amount_cents)
    end
    
    def total_paid
      total_paid_cents / 100.0
    end
    
    def payment_complete?
      total_paid_cents >= total_cents
    end
    
    def payment_pending?
      order_payments.where(status: ['pending', 'processing']).exists?
    end
    
    def latest_payment
      order_payments.order(created_at: :desc).first
    end
    
    # Participant attribution
    def supports_participant?
      participant.present?
    end
    
    def supports_general_fundraiser?
      participant.blank?
    end
    
    def participant_name
      participant&.name || "General #{fundraiser.name}"
    end
    
    # Order lifecycle methods
    def mark_as_paid!
      update!(status: STATUS_PAID)
    end
    
    def mark_as_shipped!
      return false unless can_be_shipped?
      update!(status: STATUS_SHIPPED)
    end
    
    def mark_as_delivered!
      update!(status: STATUS_DELIVERED)
    end
    
    def mark_as_completed!
      update!(status: STATUS_COMPLETED)
    end
    
    def cancel!
      return false unless can_be_cancelled?
      
      transaction do
        # Restore inventory if items have inventory tracking
        order_items.includes(:item).each do |order_item|
          if order_item.item.track_inventory?
            order_item.item.increment!(:stock_quantity, order_item.quantity)
          end
        end
        
        update!(status: STATUS_CANCELLED)
      end
    end
    
    def refund!
      return false unless can_be_refunded?
      
      transaction do
        # Restore inventory and reverse sales tracking (enhanced for variant tracking)
        order_items.includes(:item).each do |order_item|
          item = order_item.item
          
          # Handle inventory restoration based on tracking type (priority order: variant > option > item)
          if item.track_variants?
            # NEW: Variant-level inventory restoration (highest priority)
            restore_variant_inventory!(order_item)
          elsif item.uses_option_level_inventory?
            # Option-level inventory restoration
            restore_option_inventory!(order_item)
          elsif item.track_inventory?
            # Traditional item-level inventory
            item.increment!(:stock_quantity, order_item.quantity)
          end
          
          # Reverse sales tracking (legacy variant system - will be replaced by audit system)
          if item.has_variants? && order_item.selected_options.present? && !item.track_variants?
            variant = item.find_variant_by_options(order_item.selected_options)
            if variant
              revenue = order_item.quantity * order_item.price_cents / 100.0
              # Reverse the sale by subtracting
              variant.decrement!(:total_ordered, order_item.quantity)
              variant.decrement!(:total_revenue, revenue)
            end
          end
        end
        
        update!(status: STATUS_REFUNDED)
      end
    end
    
    # Reduce inventory and track sales when order is placed (enhanced for variant tracking)
    def reduce_inventory!
      order_items.includes(:item).each do |order_item|
        item = order_item.item
        
        # Handle inventory reduction based on tracking type (priority order: variant > option > item)
        if item.track_variants?
          # NEW: Variant-level inventory tracking (highest priority)
          reduce_variant_inventory!(order_item)
        elsif item.uses_option_level_inventory?
          # Option-level inventory tracking
          reduce_option_inventory!(order_item)
        elsif item.track_inventory?
          # Item-level inventory tracking
          reduce_item_inventory!(order_item)
        end
        
        # Track sales
        revenue = order_item.quantity * order_item.price_cents / 100.0
        
        if item.track_variants? && order_item.selected_options.present?
          # Track variant sales (new system)
          variant = item.find_variant_by_options(order_item.selected_options)
          if variant
            # Note: Sales tracking for variants will be handled by audit system
            Rails.logger.info("Order #{order_number}: Sold #{order_item.quantity} units of variant #{variant.variant_name}")
          end
        elsif order_item.uses_option_groups?
          # Track option group sales
          item.track_option_sales!(order_item.selected_options, order_item.quantity, revenue)
        elsif item.has_variants? && order_item.selected_options.present?
          # Track legacy variant sales
          variant = item.find_variant_by_options(order_item.selected_options)
          if variant
            variant.add_sale!(order_item.quantity, revenue)
          end
        end
      end
    end
    
    private
    
    def assign_order_number
      Rails.logger.info("Starting assign_order_number callback")
      return if order_number.present?
      
      unless restaurant_id.present?
        Rails.logger.error("Cannot assign wholesale order number: restaurant_id is missing")
        raise "Restaurant ID is required for order number generation"
      end
      
      Rails.logger.info("Restaurant ID: #{restaurant_id}")
      
      # Generate a simple order number first, without complex dependencies
      timestamp = Time.current.strftime("%Y%m%d%H%M%S")
      random_suffix = SecureRandom.hex(3).upcase
      simple_order_number = "HAF-W-#{timestamp}-#{random_suffix}"
      
      # Ensure uniqueness
      while self.class.unscoped.exists?(restaurant_id: restaurant_id, order_number: simple_order_number)
        random_suffix = SecureRandom.hex(3).upcase
        simple_order_number = "HAF-W-#{timestamp}-#{random_suffix}"
      end
      
      self.order_number = simple_order_number
      Rails.logger.info("Assigned wholesale order number #{simple_order_number} for restaurant #{restaurant_id}")
    rescue => e
      Rails.logger.error("Error assigning wholesale order number: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      # Don't silently fail - re-raise to trigger validation error
      raise e
    end
    
    def update_participant_progress
      return unless participant.present?
      participant.recalculate_current_amount!
    end
    
    public
    
    # Wholesale-specific status methods
    def self.wholesale_statuses
      [
        { value: STATUS_PENDING, label: 'Pending', description: 'Order placed, awaiting fulfillment' },
        { value: STATUS_FULFILLED, label: 'Ready for Pickup', description: 'Items prepared and ready for pickup' },
        { value: STATUS_COMPLETED, label: 'Completed', description: 'Order picked up/delivered' },
        { value: STATUS_CANCELLED, label: 'Cancelled', description: 'Order cancelled' }
      ]
    end
    
    def self.wholesale_status_options
      wholesale_statuses.map { |s| [s[:label], s[:value]] }
    end
    
    def wholesale_can_transition_to?(new_status)
      case status
      when STATUS_PENDING, STATUS_PAID
        # Allow paid orders to transition like pending orders for backward compatibility
        [STATUS_FULFILLED, STATUS_COMPLETED, STATUS_CANCELLED].include?(new_status)
      when STATUS_FULFILLED
        # Allow corrections from fulfilled status (for admin error corrections)
        [STATUS_PENDING, STATUS_PAID, STATUS_COMPLETED, STATUS_CANCELLED].include?(new_status)
      when STATUS_COMPLETED
        # Allow corrections from completed status (for admin error corrections)
        [STATUS_PENDING, STATUS_PAID, STATUS_FULFILLED, STATUS_CANCELLED].include?(new_status)
      when STATUS_CANCELLED
        # Allow corrections from cancelled status (for admin error corrections)  
        [STATUS_PENDING, STATUS_PAID, STATUS_FULFILLED, STATUS_COMPLETED].include?(new_status)
      else
        false
      end
    end
    
    private
    
    def assign_order_number
      Rails.logger.info("Starting assign_order_number callback")
      return if order_number.present?
      
      unless restaurant_id.present?
        Rails.logger.error("Cannot assign wholesale order number: restaurant_id is missing")
        raise "Restaurant ID is required for order number generation"
      end
      
      Rails.logger.info("Restaurant ID: #{restaurant_id}")
      
      # Generate a simple order number first, without complex dependencies
      timestamp = Time.current.strftime("%Y%m%d%H%M%S")
      random_suffix = SecureRandom.hex(3).upcase
      simple_order_number = "HAF-W-#{timestamp}-#{random_suffix}"
      
      # Ensure uniqueness
      while self.class.unscoped.exists?(restaurant_id: restaurant_id, order_number: simple_order_number)
        random_suffix = SecureRandom.hex(3).upcase
        simple_order_number = "HAF-W-#{timestamp}-#{random_suffix}"
      end
      
      self.order_number = simple_order_number
      Rails.logger.info("Assigned wholesale order number #{simple_order_number} for restaurant #{restaurant_id}")
    rescue => e
      Rails.logger.error("Error assigning wholesale order number: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      # Don't silently fail - re-raise to trigger validation error
      raise e
    end
    
    def update_participant_progress
      return unless participant.present?
      participant.recalculate_current_amount!
    end
    
    def restore_inventory_on_cancellation
      restore_inventory!
      Rails.logger.info("Restored inventory for cancelled order #{order_number}")
    rescue => e
      Rails.logger.error("Failed to restore inventory for cancelled order #{order_number}: #{e.message}")
      # Don't fail the cancellation if inventory restoration fails
    end
    
    # NEW: Reduce option-level inventory for order items
    def reduce_option_inventory!(order_item)
      item = order_item.item
      tracking_group = item.option_inventory_tracking_group
      
      unless tracking_group
        raise "Item #{item.name} uses option inventory but has no tracking group"
      end
      
      # Get selected options for this order item
      selected_options = order_item.selected_options || {}
      
      # Find the selected options in the tracking group
      tracking_group_selections = selected_options[tracking_group.id.to_s]
      
      if tracking_group_selections.blank?
        raise "No options selected for inventory tracking group #{tracking_group.name} in item #{item.name}"
      end
      
      # Reduce stock for each selected option
      Array(tracking_group_selections).each do |option_id|
        option = tracking_group.options.active.find_by(id: option_id)
        
        unless option
          raise "Selected option #{option_id} not found in tracking group #{tracking_group.name}"
        end
        
        # Ensure option is still available
        unless option.available?
          raise "Selected option #{option.name} is no longer available"
        end
        
        unless option.reduce_stock!(order_item.quantity, reason: 'order_placed', order: self)
          raise "Insufficient stock for #{option.name} in #{item.name} (requested: #{order_item.quantity}, available: #{option.available_stock})"
        end
        
        Rails.logger.info("Reduced #{order_item.quantity} units from option #{option.name} (#{option.available_stock} remaining)")
      end
    end
    
    # Reduce item-level inventory for order items
    def reduce_item_inventory!(order_item)
      item = order_item.item
      
      # Check if this uses the new option group system (but not option-level inventory)
      if order_item.uses_option_groups?
        # Option group system - inventory is tracked at item level
        unless item.reduce_stock!(order_item.quantity, reason: 'order_placed', order: self)
          raise "Insufficient stock for #{order_item.variant_description}"
        end
      elsif item.has_variants? && order_item.selected_options.present?
        # Legacy variant system
        variant = item.find_variant_by_options(order_item.selected_options)
        if variant
          unless variant.reduce_stock!(order_item.quantity)
            raise "Insufficient stock for #{variant.full_display_name}"
          end
        else
          # Fallback to item-level stock if variant not found
          unless item.reduce_stock!(order_item.quantity, reason: 'order_placed', order: self)
            raise "Insufficient stock for #{item.name}"
          end
        end
      else
        # Traditional item-level inventory
        unless item.reduce_stock!(order_item.quantity, reason: 'order_placed', order: self)
          raise "Insufficient stock for #{item.name}"
        end
      end
    end
    
    # NEW: Reduce variant-level inventory for order items
    def reduce_variant_inventory!(order_item)
      item = order_item.item
      
      # Get selected options for this order item
      selected_options = order_item.selected_options || {}
      
      if selected_options.blank?
        raise "No options selected for variant-tracked item #{item.name}"
      end
      
      # Find the specific variant
      variant = item.find_variant_by_options(selected_options)
      unless variant
        variant_name = item.generate_variant_name(selected_options)
        raise "#{variant_name || 'This combination'} is not available for #{item.name}"
      end
      
      # Check if variant is still active
      unless variant.active?
        raise "#{variant.variant_name} is no longer available"
      end
      
      # Use database locking to prevent race conditions
      variant.with_lock do
        # Double-check availability after acquiring lock
        available_stock = variant.available_stock
        
        if available_stock < order_item.quantity
          raise "Insufficient stock for #{variant.variant_name}. Available: #{available_stock}, Requested: #{order_item.quantity}"
        end
        
        # Capture the old quantity before updating
        old_quantity = variant.stock_quantity
        
        # Reduce the stock quantity
        new_stock_quantity = variant.stock_quantity - order_item.quantity
        variant.update!(stock_quantity: new_stock_quantity)
        
        Rails.logger.info("Order #{order_number}: Reduced #{order_item.quantity} units from variant #{variant.variant_name} (#{variant.available_stock} remaining)")
        
        # Create audit trail entry with correct previous quantity
        Wholesale::VariantStockAudit.create_stock_record(
          variant, new_stock_quantity, 'order_placed', 
          "Order placed: #{order_number}", nil, self, old_quantity
        )
      end
    end
    
    # NEW: Restore inventory when order is cancelled (enhanced for variant tracking)
    def restore_inventory!
      order_items.includes(:item).each do |order_item|
        item = order_item.item
        
        # Handle inventory restoration based on tracking type (priority order: variant > option > item)
        if item.track_variants?
          # NEW: Variant-level inventory restoration (highest priority)
          restore_variant_inventory!(order_item)
        elsif item.uses_option_level_inventory?
          # Option-level inventory restoration
          restore_option_inventory!(order_item)
        elsif item.track_inventory?
          # Item-level inventory restoration
          restore_item_inventory!(order_item)
        end
      end
    end
    
    # NEW: Restore option-level inventory for cancelled order items
    def restore_option_inventory!(order_item)
      item = order_item.item
      tracking_group = item.option_inventory_tracking_group
      
      return unless tracking_group
      
      # Get selected options for this order item
      selected_options = order_item.selected_options || {}
      tracking_group_selections = selected_options[tracking_group.id.to_s]
      
      return if tracking_group_selections.blank?
      
      # Restore stock for each selected option
      Array(tracking_group_selections).each do |option_id|
        option = tracking_group.options.active.find_by(id: option_id)
        
        next unless option
        
        # Add the quantity back to stock
        new_quantity = (option.stock_quantity || 0) + order_item.quantity
        option.update_stock_quantity(new_quantity, 'order_cancelled', "Order #{order_number} cancelled", nil, self)
        
        Rails.logger.info("Restored #{order_item.quantity} units to option #{option.name} (#{option.available_stock} now available)")
      end
    end
    
    # NEW: Restore variant-level inventory for cancelled order items
    def restore_variant_inventory!(order_item)
      item = order_item.item
      
      # Get selected options for this order item
      selected_options = order_item.selected_options || {}
      
      return if selected_options.blank?
      
      # Find the specific variant
      variant = item.find_variant_by_options(selected_options)
      return unless variant
      
      # Use database locking to prevent race conditions
      variant.with_lock do
        # Capture the old quantity before updating
        old_quantity = variant.stock_quantity
        
        # Restore the stock quantity
        new_stock_quantity = variant.stock_quantity + order_item.quantity
        variant.update!(stock_quantity: new_stock_quantity)
        
        Rails.logger.info("Order #{order_number}: Restored #{order_item.quantity} units to variant #{variant.variant_name} (#{variant.available_stock} now available)")
        
        # Create audit trail entry with correct previous quantity
        Wholesale::VariantStockAudit.create_stock_record(
          variant, new_stock_quantity, 'order_cancelled', 
          "Order cancelled: #{order_number}", nil, self, old_quantity
        )
      end
    end
    
    # Restore item-level inventory for cancelled order items
    def restore_item_inventory!(order_item)
      item = order_item.item
      
      # Add the quantity back to stock
      new_quantity = (item.stock_quantity || 0) + order_item.quantity
      item.update_stock_quantity(new_quantity, 'order_cancelled', "Order #{order_number} cancelled", nil, self)
      
      Rails.logger.info("Restored #{order_item.quantity} units to item #{item.name} (#{item.available_quantity} now available)")
    end
  end
end