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
        # Restore inventory if items have inventory tracking
        order_items.includes(:item).each do |order_item|
          if order_item.item.track_inventory?
            order_item.item.increment!(:stock_quantity, order_item.quantity)
          end
        end
        
        update!(status: STATUS_REFUNDED)
      end
    end
    
    # Reduce inventory when order is placed
    def reduce_inventory!
      order_items.includes(:item).each do |order_item|
        item = order_item.item
        if item.track_inventory?
          unless item.reduce_stock!(order_item.quantity)
            raise "Insufficient stock for #{item.name}"
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
        [STATUS_COMPLETED, STATUS_CANCELLED].include?(new_status)
      when STATUS_COMPLETED, STATUS_CANCELLED
        false # Final states
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
  end
end