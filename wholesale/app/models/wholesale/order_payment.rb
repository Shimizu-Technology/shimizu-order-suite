# app/models/wholesale/order_payment.rb

module Wholesale
  class OrderPayment < ApplicationRecord
    # Payment status constants
    STATUS_PENDING = "pending"
    STATUS_PROCESSING = "processing"
    STATUS_COMPLETED = "completed"
    STATUS_FAILED = "failed"
    STATUS_CANCELLED = "cancelled"
    STATUS_REFUNDED = "refunded"
    
    # Payment method constants
    METHOD_STRIPE = "stripe"
    METHOD_PAYPAL = "paypal"
    METHOD_CASH = "cash"
    METHOD_CHECK = "check"
    
    # Associations
    belongs_to :order, class_name: 'Wholesale::Order'
    
    # Validations
    validates :amount_cents, presence: true, numericality: { greater_than: 0 }
    validates :payment_method, presence: true, inclusion: { in: [METHOD_STRIPE, METHOD_PAYPAL, METHOD_CASH, METHOD_CHECK] }
    validates :status, presence: true, inclusion: { in: [
      STATUS_PENDING, STATUS_PROCESSING, STATUS_COMPLETED, 
      STATUS_FAILED, STATUS_CANCELLED, STATUS_REFUNDED
    ]}
    validates :stripe_payment_intent_id, uniqueness: true, allow_blank: true
    validates :stripe_charge_id, uniqueness: true, allow_blank: true
    validates :transaction_id, uniqueness: { scope: :payment_method }, allow_blank: true
    
    # Custom validations
    validate :stripe_fields_for_stripe_payments
    validate :amount_not_greater_than_order_total
    
    # Callbacks
    after_update :update_order_status, if: -> { saved_change_to_status? }
    before_validation :set_processed_at, if: -> { status_changed? && completed? }
    
    # Scopes
    scope :by_status, ->(status) { where(status: status) }
    scope :by_method, ->(method) { where(payment_method: method) }
    scope :pending, -> { where(status: STATUS_PENDING) }
    scope :processing, -> { where(status: STATUS_PROCESSING) }
    scope :completed, -> { where(status: STATUS_COMPLETED) }
    scope :failed, -> { where(status: STATUS_FAILED) }
    scope :cancelled, -> { where(status: STATUS_CANCELLED) }
    scope :refunded, -> { where(status: STATUS_REFUNDED) }
    scope :successful, -> { where(status: STATUS_COMPLETED) }
    scope :stripe_payments, -> { where(payment_method: METHOD_STRIPE) }
    scope :recent, -> { order(created_at: :desc) }
    
    # Amount handling (in cents)
    def amount
      (amount_cents || 0) / 100.0
    end
    
    def amount=(money_amount)
      if money_amount.is_a?(String)
        self.amount_cents = (money_amount.to_f * 100).round
      else
        self.amount_cents = (money_amount.to_f * 100).round
      end
    end
    
    # Status helpers
    def pending?
      status == STATUS_PENDING
    end
    
    def processing?
      status == STATUS_PROCESSING
    end
    
    def completed?
      status == STATUS_COMPLETED
    end
    
    def failed?
      status == STATUS_FAILED
    end
    
    def cancelled?
      status == STATUS_CANCELLED
    end
    
    def refunded?
      status == STATUS_REFUNDED
    end
    
    def successful?
      completed?
    end
    
    def can_be_refunded?
      completed? && !refunded?
    end
    
    def can_be_cancelled?
      pending? || processing?
    end
    
    # Payment method helpers
    def stripe_payment?
      payment_method == METHOD_STRIPE
    end
    
    def paypal_payment?
      payment_method == METHOD_PAYPAL
    end
    
    def cash_payment?
      payment_method == METHOD_CASH
    end
    
    def check_payment?
      payment_method == METHOD_CHECK
    end
    
    # Stripe-specific helpers
    def stripe_payment_intent
      return nil unless stripe_payment? && stripe_payment_intent_id.present?
      
      begin
        # This would integrate with Stripe SDK
        # Stripe::PaymentIntent.retrieve(stripe_payment_intent_id)
        { id: stripe_payment_intent_id, status: 'unknown' }
      rescue => e
        Rails.logger.error("Error retrieving Stripe Payment Intent: #{e.message}")
        nil
      end
    end
    
    def stripe_charge
      return nil unless stripe_payment? && stripe_charge_id.present?
      
      begin
        # This would integrate with Stripe SDK
        # Stripe::Charge.retrieve(stripe_charge_id)
        { id: stripe_charge_id, status: 'unknown' }
      rescue => e
        Rails.logger.error("Error retrieving Stripe Charge: #{e.message}")
        nil
      end
    end
    
    def stripe_dashboard_url
      return nil unless stripe_payment_intent_id.present?
      
      # Link to Stripe dashboard (would need actual Stripe account info)
      "https://dashboard.stripe.com/payments/#{stripe_payment_intent_id}"
    end
    
    # Payment lifecycle methods
    def mark_as_processing!
      return false unless pending?
      update!(status: STATUS_PROCESSING)
    end
    
    def mark_as_completed!(transaction_id: nil, stripe_charge_id: nil)
      updates = { 
        status: STATUS_COMPLETED,
        processed_at: Time.current
      }
      
      updates[:transaction_id] = transaction_id if transaction_id.present?
      updates[:stripe_charge_id] = stripe_charge_id if stripe_charge_id.present?
      
      update!(updates)
    end
    
    def mark_as_failed!(error_message = nil)
      updates = { status: STATUS_FAILED }
      
      if error_message.present?
        updates[:payment_data] = (payment_data || {}).merge(
          error_message: error_message,
          failed_at: Time.current
        )
      end
      
      update!(updates)
    end
    
    def cancel!
      return false unless can_be_cancelled?
      update!(status: STATUS_CANCELLED)
    end
    
    def refund!(refund_amount_cents = nil)
      return false unless can_be_refunded?
      
      refund_amount_cents ||= amount_cents
      
      # Create a new payment record for the refund
      refund_payment = order.order_payments.create!(
        amount_cents: -refund_amount_cents,
        payment_method: payment_method,
        status: STATUS_COMPLETED,
        transaction_id: "refund_#{transaction_id}",
        stripe_payment_intent_id: stripe_payment_intent_id,
        stripe_charge_id: stripe_charge_id,
        processed_at: Time.current,
        payment_data: {
          refund_of: id,
          original_payment: payment_data
        }
      )
      
      # Mark this payment as refunded if fully refunded
      if refund_amount_cents >= amount_cents
        update!(status: STATUS_REFUNDED)
      end
      
      refund_payment
    end
    
    # Payment data helpers
    def add_payment_data(key, value)
      self.payment_data = (payment_data || {}).merge(key => value)
      save!
    end
    
    def get_payment_data(key)
      payment_data&.dig(key.to_s)
    end
    
    def stripe_metadata
      payment_data&.dig('stripe_metadata') || {}
    end
    
    def error_message
      payment_data&.dig('error_message')
    end
    
    # Order relationship helpers
    def order_number
      order&.order_number
    end
    
    def customer_email
      order&.customer_email
    end
    
    def fundraiser_name
      order&.fundraiser&.name
    end
    
    def participant_name
      order&.participant_name
    end
    
    private
    
    def stripe_fields_for_stripe_payments
      return unless stripe_payment?
      
      if pending? || processing?
        if stripe_payment_intent_id.blank?
          errors.add(:stripe_payment_intent_id, 'is required for Stripe payments')
        end
      end
    end
    
    def amount_not_greater_than_order_total
      return unless order.present? && amount_cents.present?
      
      if amount_cents > order.total_cents
        errors.add(:amount_cents, 'cannot be greater than order total')
      end
    end
    
    def update_order_status
      return unless order.present?
      
      case status
      when STATUS_COMPLETED
        # Check if order is fully paid
        if order.payment_complete?
          order.mark_as_paid!
        end
      when STATUS_FAILED, STATUS_CANCELLED
        # If this was the only payment attempt and it failed, keep order as pending
        # Otherwise, check if there are other successful payments
        unless order.payment_complete?
          order.update!(status: 'pending') if order.paid?
        end
      end
    end
    
    def set_processed_at
      self.processed_at = Time.current
    end
  end
end